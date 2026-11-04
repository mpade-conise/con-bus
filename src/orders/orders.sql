-- Order management integration. Run after authentication.sql, homepage.sql and sellers.sql.
create extension if not exists pgcrypto;

alter table public.seller_orders
  add column if not exists discount_amount numeric(12,2) not null default 0 check(discount_amount>=0),
  add column if not exists delivery_method text,
  add column if not exists delivery_address jsonb not null default '{}'::jsonb,
  add column if not exists payment_method text,
  add column if not exists customer_note text,
  add column if not exists cancellation_reason text,
  add column if not exists return_reason text,
  add column if not exists return_requested_at timestamptz,
  add column if not exists return_status text not null default 'none';

alter table public.seller_orders drop constraint if exists seller_orders_status_check;
alter table public.seller_orders add constraint seller_orders_status_check
  check(status in('pending','confirmed','processing','ready_for_delivery','shipped','delivered','cancelled','refunded'));
alter table public.seller_orders drop constraint if exists seller_orders_payment_status_check;
alter table public.seller_orders add constraint seller_orders_payment_status_check
  check(payment_status in('pending','paid','failed','refunded'));
alter table public.seller_orders drop constraint if exists seller_orders_return_status_check;
alter table public.seller_orders add constraint seller_orders_return_status_check
  check(return_status in('none','requested','approved','rejected','received','refunded'));

create table if not exists public.seller_order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.seller_orders(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type text not null,
  old_status text,
  new_status text,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists seller_order_events_order_idx on public.seller_order_events(order_id,created_at);

alter table public.seller_order_events enable row level security;
drop policy if exists "Order participants read order events" on public.seller_order_events;
create policy "Order participants read order events" on public.seller_order_events for select to authenticated
using(exists(select 1 from public.seller_orders o where o.id=order_id and (o.customer_id=auth.uid() or o.seller_id=auth.uid())));
grant select on public.seller_order_events to authenticated;

drop policy if exists "Customers read own seller orders" on public.seller_orders;
create policy "Customers read own seller orders" on public.seller_orders for select to authenticated
using(customer_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='customer' and p.is_active));
grant select on public.seller_orders to authenticated;

create or replace function public.record_seller_order_event()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.seller_order_events(order_id,actor_id,event_type,new_status,note)
    values(new.id,new.customer_id,'order_placed',new.status,'Order placed by customer');
  elsif new.status is distinct from old.status then
    insert into public.seller_order_events(order_id,actor_id,event_type,old_status,new_status,note)
    values(new.id,auth.uid(),'status_changed',old.status,new.status,case when new.status='cancelled' then coalesce(new.cancellation_reason,'Order cancelled') else 'Order status updated' end);
    if new.status='cancelled' and old.status<>'cancelled' then
      update public.products p set stock=p.stock+(x.quantity)::integer
      from jsonb_to_recordset(old.items) as x(product_id uuid,quantity integer)
      where p.id=x.product_id and p.seller_id=old.seller_id;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists seller_order_event_trigger on public.seller_orders;
create trigger seller_order_event_trigger after insert or update of status on public.seller_orders
for each row execute function public.record_seller_order_event();

create or replace function public.enforce_seller_order_transition()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status='pending' and new.status in('confirmed','cancelled')) or
      (old.status='confirmed' and new.status in('processing','cancelled')) or
      (old.status='processing' and new.status in('ready_for_delivery','cancelled')) or
      (old.status='ready_for_delivery' and new.status in('shipped','cancelled')) or
      (old.status='shipped' and new.status='delivered') or
      (old.status='delivered' and new.status='refunded')
    ) then raise exception 'This order status transition is not allowed.'; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists seller_order_transition_guard on public.seller_orders;
create trigger seller_order_transition_guard before update of status on public.seller_orders
for each row execute function public.enforce_seller_order_transition();

create or replace function public.place_marketplace_order(
  p_items jsonb,
  p_delivery_address jsonb,
  p_delivery_method text,
  p_payment_method text,
  p_customer_note text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_seller uuid;
  v_product record;
  v_item jsonb;
  v_items jsonb;
  v_subtotal numeric(12,2);
  v_total numeric(12,2);
  v_grand_total numeric(12,2);
  v_order_id uuid;
  v_order_number text;
  v_result jsonb:='[]'::jsonb;
  v_qty integer;
  v_name text;
begin
  if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and role='customer' and is_active) then
    raise exception 'A verified customer account is required.';
  end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Your cart is empty.'; end if;
  if (select count(*) from jsonb_array_elements(p_items))<>(select count(*) from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid) then raise exception 'One or more products in your cart no longer exist.'; end if;
  if coalesce(p_delivery_address->>'name','')='' or coalesce(p_delivery_address->>'phone','')='' or coalesce(p_delivery_address->>'city','')='' or coalesce(p_delivery_address->>'address','')='' then
    raise exception 'Enter the recipient name, phone, city and delivery address.';
  end if;
  if p_delivery_method not in('home_delivery','pickup') then raise exception 'Choose a valid delivery method.'; end if;
  if p_payment_method not in('cash_on_delivery','mobile_money','bank_transfer') then raise exception 'Choose a valid payment method.'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where coalesce((i->>'quantity')::integer,0)<1) then raise exception 'Invalid product quantity.'; end if;

  for v_seller in select distinct p.seller_id
    from jsonb_array_elements(p_items) i
    join public.products p on p.id=(i->>'id')::uuid
    order by p.seller_id
  loop
    v_items:='[]'::jsonb;
    v_subtotal:=0;
    v_grand_total:=0;
    for v_item in select i from jsonb_array_elements(p_items) i
      join public.products p on p.id=(i->>'id')::uuid
      where p.seller_id=v_seller
    loop
      v_qty:=(v_item->>'quantity')::integer;
      select id,name,title,price,discount_price,sale_price,stock,is_active,status,visibility,seller_id
      into v_product from public.products where id=(v_item->>'id')::uuid for update;
      if not found or v_product.seller_id<>v_seller or not v_product.is_active or v_product.status<>'published' or v_product.visibility<>'public' then
        raise exception 'A selected product is no longer available.';
      end if;
      if v_product.stock<v_qty then raise exception 'Insufficient stock for %.',coalesce(v_product.name,v_product.title); end if;
      v_name:=coalesce(v_product.name,v_product.title,'Product');
      v_total:=coalesce(v_product.discount_price,v_product.sale_price,v_product.price);
      v_subtotal:=v_subtotal+(v_product.price*v_qty);
      v_grand_total:=v_grand_total+(v_total*v_qty);
      v_items:=v_items||jsonb_build_array(jsonb_build_object('product_id',v_product.id,'name',v_name,'quantity',v_qty,'unit_price',v_total,'regular_price',v_product.price,'image_url',(select p.image_url from public.products p where p.id=v_product.id)));
      update public.products set stock=stock-v_qty where id=v_product.id;
    end loop;
    v_order_number:='MH-'||to_char(now(),'YYMMDD')||'-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8));
    insert into public.seller_orders(seller_id,customer_id,customer_name,order_number,items,subtotal,shipping_amount,discount_amount,total_amount,currency,status,payment_status,delivery_method,delivery_address,payment_method,customer_note)
    values(v_seller,v_uid,(select full_name from public.profiles where id=v_uid),v_order_number,v_items,v_subtotal,0,v_subtotal-v_grand_total,v_grand_total,'MWK','pending','pending',p_delivery_method,p_delivery_address,p_payment_method,nullif(p_customer_note,''))
    returning id into v_order_id;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('id',v_order_id,'order_number',v_order_number,'seller_id',v_seller,'total_amount',v_grand_total));
  end loop;
  if jsonb_array_length(v_result)=0 then raise exception 'No valid products were found in your cart.'; end if;
  return v_result;
end;
$$;
revoke all on function public.place_marketplace_order(jsonb,jsonb,text,text,text) from public;
grant execute on function public.place_marketplace_order(jsonb,jsonb,text,text,text) to authenticated;

create or replace function public.cancel_marketplace_order(p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.seller_orders set status='cancelled',cancellation_reason=nullif(p_reason,'')
  where id=p_order_id and customer_id=auth.uid() and status in('pending','confirmed');
  if not found then raise exception 'This order can no longer be cancelled.'; end if;
end;
$$;
revoke all on function public.cancel_marketplace_order(uuid,text) from public;
grant execute on function public.cancel_marketplace_order(uuid,text) to authenticated;

create or replace function public.request_marketplace_return(p_order_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if coalesce(trim(p_reason),'')='' then raise exception 'Provide a reason for the return.'; end if;
  update public.seller_orders set return_status='requested',return_reason=trim(p_reason),return_requested_at=now()
  where id=p_order_id and customer_id=auth.uid() and status='delivered' and return_status='none';
  if not found then raise exception 'A return can only be requested once for a delivered order.'; end if;
  insert into public.seller_order_events(order_id,actor_id,event_type,note)
  values(p_order_id,auth.uid(),'return_requested',trim(p_reason));
end;
$$;
revoke all on function public.request_marketplace_return(uuid,text) from public;
grant execute on function public.request_marketplace_return(uuid,text) to authenticated;

-- Enable realtime for incoming seller orders and customer tracking timelines when Supabase Realtime is available.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='seller_orders') then
      execute 'alter publication supabase_realtime add table public.seller_orders';
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='seller_order_events') then
      execute 'alter publication supabase_realtime add table public.seller_order_events';
    end if;
  end if;
end $$;
