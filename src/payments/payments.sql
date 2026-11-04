-- Marketplace payments and seller finance. Run after orders.sql.
create extension if not exists pgcrypto;

create table if not exists public.marketplace_settings(
  id boolean primary key default true check(id),
  platform_fee_percent numeric(5,2) not null default 0 check(platform_fee_percent>=0 and platform_fee_percent<=30),
  minimum_withdrawal numeric(12,2) not null default 0 check(minimum_withdrawal>=0),
  updated_at timestamptz not null default now()
);
insert into public.marketplace_settings(id) values(true) on conflict(id) do nothing;
alter table public.marketplace_settings enable row level security;
drop policy if exists "Administrators manage marketplace settings" on public.marketplace_settings;
create policy "Administrators manage marketplace settings" on public.marketplace_settings for all to authenticated
using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'))
with check(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));

create table if not exists public.marketplace_transactions(
  id uuid primary key default gen_random_uuid(),
  tx_ref text not null unique,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  provider text not null default 'paychangu',
  payment_method text not null check(payment_method in('airtel_money','tnm_mpamba','card')),
  amount numeric(12,2) not null check(amount>0),
  provider_fee numeric(12,2) not null default 0 check(provider_fee>=0),
  currency text not null default 'MWK' check(currency='MWK'),
  status text not null default 'pending' check(status in('pending','successful','failed','expired','refund_pending','refunded')),
  checkout_url text,
  provider_reference text,
  provider_charge_id text,
  provider_status text,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists marketplace_transactions_customer_idx on public.marketplace_transactions(customer_id,created_at desc);
create index if not exists marketplace_transactions_status_idx on public.marketplace_transactions(status,created_at);

create table if not exists public.payment_order_allocations(
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.marketplace_transactions(id) on delete cascade,
  order_id uuid not null references public.seller_orders(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  gross_amount numeric(12,2) not null check(gross_amount>=0),
  platform_fee numeric(12,2) not null check(platform_fee>=0),
  seller_net numeric(12,2) not null check(seller_net>=0),
  created_at timestamptz not null default now(),
  unique(transaction_id,order_id)
);
create index if not exists payment_allocations_order_idx on public.payment_order_allocations(order_id);

create table if not exists public.seller_earnings(
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete restrict,
  order_id uuid not null unique references public.seller_orders(id) on delete restrict,
  transaction_id uuid not null references public.marketplace_transactions(id) on delete restrict,
  gross_amount numeric(12,2) not null,
  platform_fee numeric(12,2) not null,
  net_amount numeric(12,2) not null,
  status text not null default 'pending' check(status in('pending','available','withdrawn','reversed')),
  created_at timestamptz not null default now(),
  available_at timestamptz,
  updated_at timestamptz not null default now()
);
create index if not exists seller_earnings_seller_idx on public.seller_earnings(seller_id,status,created_at desc);

create table if not exists public.seller_withdrawals(
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete restrict,
  reference text not null unique,
  amount numeric(12,2) not null check(amount>0),
  currency text not null default 'MWK' check(currency='MWK'),
  payout_method text not null check(payout_method in('airtel_money','tnm_mpamba','bank_transfer')),
  destination jsonb not null,
  status text not null default 'pending' check(status in('pending','approved','processing','paid','rejected','failed')),
  provider_reference text,
  admin_note text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists seller_withdrawals_seller_idx on public.seller_withdrawals(seller_id,requested_at desc);

create table if not exists public.marketplace_refund_requests(
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.seller_orders(id) on delete restrict,
  transaction_id uuid not null references public.marketplace_transactions(id) on delete restrict,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0),
  reason text not null,
  status text not null default 'requested' check(status in('requested','approved','rejected','processing','refunded','failed')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists one_open_refund_per_order on public.marketplace_refund_requests(order_id) where status in('requested','approved','processing');

create table if not exists public.marketplace_notifications(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null,
  title text not null,
  message text not null,
  related_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists marketplace_notifications_user_idx on public.marketplace_notifications(user_id,created_at desc);

create table if not exists public.payment_reconciliation(
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid references public.marketplace_transactions(id) on delete set null,
  tx_ref text not null,
  provider_reference text,
  expected_amount numeric(12,2),
  received_amount numeric(12,2),
  currency text,
  result text not null,
  notes text,
  reconciled_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.marketplace_transactions enable row level security;
alter table public.payment_order_allocations enable row level security;
alter table public.seller_earnings enable row level security;
alter table public.seller_withdrawals enable row level security;
alter table public.marketplace_refund_requests enable row level security;
alter table public.marketplace_notifications enable row level security;
alter table public.payment_reconciliation enable row level security;

drop policy if exists "Customers read own transactions" on public.marketplace_transactions;
create policy "Customers read own transactions" on public.marketplace_transactions for select to authenticated using(customer_id=auth.uid());
drop policy if exists "Administrators read all transactions" on public.marketplace_transactions;
create policy "Administrators read all transactions" on public.marketplace_transactions for select to authenticated using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));
drop policy if exists "Sellers read own earnings" on public.seller_earnings;
create policy "Sellers read own earnings" on public.seller_earnings for select to authenticated using(seller_id=auth.uid());
drop policy if exists "Administrators manage earnings" on public.seller_earnings;
create policy "Administrators manage earnings" on public.seller_earnings for all to authenticated using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator')) with check(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));
drop policy if exists "Sellers read own withdrawals" on public.seller_withdrawals;
create policy "Sellers read own withdrawals" on public.seller_withdrawals for select to authenticated using(seller_id=auth.uid());
drop policy if exists "Administrators manage withdrawals" on public.seller_withdrawals;
create policy "Administrators manage withdrawals" on public.seller_withdrawals for all to authenticated using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator')) with check(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));
drop policy if exists "Customers read own refund requests" on public.marketplace_refund_requests;
create policy "Customers read own refund requests" on public.marketplace_refund_requests for select to authenticated using(customer_id=auth.uid());
drop policy if exists "Sellers read refund requests for own orders" on public.marketplace_refund_requests;
create policy "Sellers read refund requests for own orders" on public.marketplace_refund_requests for select to authenticated using(seller_id=auth.uid());
drop policy if exists "Administrators manage refund requests" on public.marketplace_refund_requests;
create policy "Administrators manage refund requests" on public.marketplace_refund_requests for all to authenticated using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator')) with check(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));
drop policy if exists "Users read own marketplace notifications" on public.marketplace_notifications;
create policy "Users read own marketplace notifications" on public.marketplace_notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists "Users update own marketplace notifications" on public.marketplace_notifications;
create policy "Users update own marketplace notifications" on public.marketplace_notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "Administrators read reconciliation" on public.payment_reconciliation;
create policy "Administrators read reconciliation" on public.payment_reconciliation for select to authenticated using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));

grant select on public.marketplace_transactions,public.seller_earnings,public.seller_withdrawals,public.marketplace_refund_requests,public.marketplace_notifications to authenticated;

create or replace function public.create_marketplace_payment_intent(p_order_ids uuid[],p_method text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_tx_id uuid;
  v_tx_ref text:='MH-'||upper(replace(gen_random_uuid()::text,'-',''));
  v_amount numeric(12,2);
  v_fee_rate numeric(5,2);
  v_name text;
  v_email text;
  v_order record;
begin
  if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and role='customer' and is_active) then raise exception 'A verified customer account is required.'; end if;
  if p_method not in('airtel_money','tnm_mpamba','card') then raise exception 'Unsupported payment method.'; end if;
  if coalesce(array_length(p_order_ids,1),0)=0 then raise exception 'Select at least one order to pay.'; end if;
  if (select count(distinct x) from unnest(p_order_ids) x)<>array_length(p_order_ids,1) then raise exception 'Duplicate order selected.'; end if;
  perform 1 from public.seller_orders where id=any(p_order_ids) and customer_id=v_uid for update;
  if (select count(*) from public.seller_orders where id=any(p_order_ids) and customer_id=v_uid and status not in('cancelled','refunded') and payment_status in('pending','failed'))<>array_length(p_order_ids,1) then raise exception 'One or more orders cannot be paid.'; end if;
  update public.marketplace_transactions t set status='expired',updated_at=now()
  where t.status='pending' and exists(select 1 from public.payment_order_allocations a where a.transaction_id=t.id and a.order_id=any(p_order_ids));
  select platform_fee_percent into v_fee_rate from public.marketplace_settings where id=true;
  select sum(total_amount) into v_amount from public.seller_orders where id=any(p_order_ids) and customer_id=v_uid;
  if coalesce(v_amount,0)<=0 or v_amount<>trunc(v_amount) or v_amount>2147483647 then raise exception 'Payment amount must be a whole MWK amount within the provider limit.'; end if;
  insert into public.marketplace_transactions(tx_ref,customer_id,payment_method,amount,currency,status)
  values(v_tx_ref,v_uid,p_method,v_amount,'MWK','pending') returning id into v_tx_id;
  for v_order in select * from public.seller_orders where id=any(p_order_ids) and customer_id=v_uid loop
    insert into public.payment_order_allocations(transaction_id,order_id,seller_id,gross_amount,platform_fee,seller_net)
    values(v_tx_id,v_order.id,v_order.seller_id,v_order.total_amount,round(v_order.total_amount*v_fee_rate/100,2),v_order.total_amount-round(v_order.total_amount*v_fee_rate/100,2));
  end loop;
  update public.seller_orders set payment_method=p_method,payment_status='pending' where id=any(p_order_ids) and customer_id=v_uid;
  select full_name into v_name from public.profiles where id=v_uid;
  v_email:=auth.jwt()->>'email';
  return jsonb_build_object('transaction_id',v_tx_id,'tx_ref',v_tx_ref,'amount',v_amount,'currency','MWK','first_name',split_part(coalesce(v_name,''),' ',1),'last_name',nullif(substr(coalesce(v_name,''),length(split_part(coalesce(v_name,''),' ',1))+2),''),'email',v_email);
end;
$$;
revoke all on function public.create_marketplace_payment_intent(uuid[],text) from public;
grant execute on function public.create_marketplace_payment_intent(uuid[],text) to authenticated;

create or replace function public.finalize_marketplace_payment(p_tx_ref text,p_provider_reference text,p_amount numeric,p_currency text,p_provider_status text,p_provider_fee numeric default 0)
returns void language plpgsql security definer set search_path=public as $$
declare v_tx public.marketplace_transactions%rowtype;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Service role required.'; end if;
  select * into v_tx from public.marketplace_transactions where tx_ref=p_tx_ref for update;
  if not found then raise exception 'Unknown transaction reference.'; end if;
  if v_tx.status='successful' then return; end if;
  if v_tx.status<>'pending' then raise exception 'Transaction is not pending.'; end if;
  if p_provider_status<>'success' or p_currency<>'MWK' or p_amount<>v_tx.amount then raise exception 'Provider payment details do not match the expected transaction.'; end if;
  if coalesce(p_provider_fee,0)<0 then raise exception 'Invalid provider fee.'; end if;
  update public.marketplace_transactions set status='successful',provider_reference=p_provider_reference,provider_status=p_provider_status,provider_fee=coalesce(p_provider_fee,0),completed_at=now(),updated_at=now() where id=v_tx.id;
  update public.seller_orders o set payment_status='paid' from public.payment_order_allocations a where a.transaction_id=v_tx.id and a.order_id=o.id;
  insert into public.seller_earnings(seller_id,order_id,transaction_id,gross_amount,platform_fee,net_amount)
  select seller_id,order_id,v_tx.id,gross_amount,platform_fee,seller_net from public.payment_order_allocations where transaction_id=v_tx.id
  on conflict(order_id) do nothing;
  insert into public.payment_reconciliation(transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes)
  values(v_tx.id,v_tx.tx_ref,p_provider_reference,v_tx.amount,p_amount,p_currency,'matched','PayChangu verification succeeded.');
end;
$$;
revoke all on function public.finalize_marketplace_payment(text,text,numeric,text,text,numeric) from public;
grant execute on function public.finalize_marketplace_payment(text,text,numeric,text,text,numeric) to service_role;

create or replace function public.fail_marketplace_payment(p_tx_ref text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_tx public.marketplace_transactions%rowtype;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Service role required.'; end if;
  select * into v_tx from public.marketplace_transactions where tx_ref=p_tx_ref for update;
  if not found or v_tx.status<>'pending' then return; end if;
  update public.marketplace_transactions set status='failed',failure_reason=left(coalesce(p_reason,'Payment failed'),500),updated_at=now() where id=v_tx.id;
  update public.seller_orders o set payment_status='failed' from public.payment_order_allocations a where a.transaction_id=v_tx.id and a.order_id=o.id and o.payment_status<>'paid';
  insert into public.payment_reconciliation(transaction_id,tx_ref,expected_amount,currency,result,notes)
  values(v_tx.id,v_tx.tx_ref,v_tx.amount,v_tx.currency,'failed',left(coalesce(p_reason,'Payment failed'),500));
end;
$$;
revoke all on function public.fail_marketplace_payment(text,text) from public;
grant execute on function public.fail_marketplace_payment(text,text) to service_role;

create or replace function public.release_seller_earnings_on_delivery()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='delivered' and old.status is distinct from new.status then
    update public.seller_earnings set status='available',available_at=now(),updated_at=now()
    where order_id=new.id and status='pending';
  end if;
  return new;
end;
$$;
drop trigger if exists release_seller_earnings_trigger on public.seller_orders;
create trigger release_seller_earnings_trigger after update of status on public.seller_orders for each row execute function public.release_seller_earnings_on_delivery();

create or replace function public.request_seller_withdrawal(p_amount numeric,p_method text,p_destination jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); v_available numeric(12,2); v_reserved numeric(12,2); v_min numeric(12,2); v_id uuid;
begin
  if v_uid is null then raise exception 'Sign in required.'; end if;
  perform 1 from public.profiles where id=v_uid and role='seller' and is_active for update;
  if not found then raise exception 'An active seller account is required.'; end if;
  if p_method not in('airtel_money','tnm_mpamba','bank_transfer') then raise exception 'Invalid payout method.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Enter a valid withdrawal amount.'; end if;
  if coalesce(p_destination->>'account_name','')='' or coalesce(p_destination->>'account_number','')='' then raise exception 'Enter payout account name and number.'; end if;
  select minimum_withdrawal into v_min from public.marketplace_settings where id=true;
  select coalesce(sum(net_amount),0) into v_available from public.seller_earnings where seller_id=v_uid and status='available';
  select coalesce(sum(amount),0) into v_reserved from public.seller_withdrawals where seller_id=v_uid and status in('pending','approved','processing','paid');
  if p_amount<v_min then raise exception 'Minimum withdrawal is % MWK.',v_min; end if;
  if p_amount>v_available-v_reserved then raise exception 'Insufficient available earnings.'; end if;
  insert into public.seller_withdrawals(seller_id,reference,amount,payout_method,destination)
  values(v_uid,'WD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,14)),p_amount,p_method,p_destination) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.request_seller_withdrawal(numeric,text,jsonb) from public;
grant execute on function public.request_seller_withdrawal(numeric,text,jsonb) to authenticated;

create or replace function public.request_marketplace_refund(p_order_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_order public.seller_orders%rowtype; v_tx_id uuid; v_id uuid;
begin
  select * into v_order from public.seller_orders where id=p_order_id and customer_id=auth.uid() for update;
  if not found or v_order.payment_status<>'paid' or v_order.status not in('cancelled','delivered') then raise exception 'Only paid cancelled or delivered orders can be submitted for refund review.'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Provide a refund reason.'; end if;
  select a.transaction_id into v_tx_id from public.payment_order_allocations a join public.marketplace_transactions t on t.id=a.transaction_id where a.order_id=p_order_id and t.status='successful' limit 1;
  if v_tx_id is null then raise exception 'No successful online payment was found for this order.'; end if;
  insert into public.marketplace_refund_requests(order_id,transaction_id,customer_id,seller_id,amount,reason)
  values(v_order.id,v_tx_id,auth.uid(),v_order.seller_id,v_order.total_amount,trim(p_reason)) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.request_marketplace_refund(uuid,text) from public;
grant execute on function public.request_marketplace_refund(uuid,text) to authenticated;

create or replace function public.notify_marketplace_payment_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status is distinct from old.status and new.status in('successful','failed','refunded') then
    insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
    values(new.customer_id,'payment_'||new.status,'Payment '||new.status,case when new.status='successful' then 'Your payment was verified successfully.' when new.status='failed' then 'Your payment failed. You can retry from your order history.' else 'Your payment refund has been recorded.' end,new.id);
    if new.status='successful' then
      insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
      select distinct a.seller_id,'seller_payment_received','Payment received','A customer payment for one of your orders has been verified.',new.id from public.payment_order_allocations a where a.transaction_id=new.id;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists marketplace_payment_notification_trigger on public.marketplace_transactions;
create trigger marketplace_payment_notification_trigger after update of status on public.marketplace_transactions for each row execute function public.notify_marketplace_payment_change();

-- Extend checkout payment choices to the supported online rails.
create or replace function public.place_marketplace_order(
  p_items jsonb,p_delivery_address jsonb,p_delivery_method text,p_payment_method text,p_customer_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid(); v_seller uuid; v_product record; v_item jsonb; v_items jsonb;
  v_subtotal numeric(12,2); v_total numeric(12,2); v_grand_total numeric(12,2);
  v_order_id uuid; v_order_number text; v_result jsonb:='[]'::jsonb; v_qty integer; v_name text;
begin
  if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and role='customer' and is_active) then raise exception 'A verified customer account is required.'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Your cart is empty.'; end if;
  if (select count(*) from jsonb_array_elements(p_items))<>(select count(*) from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid) then raise exception 'One or more products in your cart no longer exist.'; end if;
  if coalesce(p_delivery_address->>'name','')='' or coalesce(p_delivery_address->>'phone','')='' or coalesce(p_delivery_address->>'city','')='' or coalesce(p_delivery_address->>'address','')='' then raise exception 'Enter the recipient name, phone, city and delivery address.'; end if;
  if p_delivery_method not in('home_delivery','pickup') then raise exception 'Choose a valid delivery method.'; end if;
  if p_payment_method not in('cash_on_delivery','airtel_money','tnm_mpamba','card') then raise exception 'Choose a valid payment method.'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where coalesce((i->>'quantity')::integer,0)<1) then raise exception 'Invalid product quantity.'; end if;
  for v_seller in select distinct p.seller_id from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid order by p.seller_id loop
    v_items:='[]'::jsonb; v_subtotal:=0; v_grand_total:=0;
    for v_item in select i from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid where p.seller_id=v_seller loop
      v_qty:=(v_item->>'quantity')::integer;
      select id,name,title,price,discount_price,sale_price,stock,is_active,status,visibility,seller_id into v_product from public.products where id=(v_item->>'id')::uuid for update;
      if not found or v_product.seller_id<>v_seller or not v_product.is_active or v_product.status<>'published' or v_product.visibility<>'public' then raise exception 'A selected product is no longer available.'; end if;
      if v_product.stock<v_qty then raise exception 'Insufficient stock for %.',coalesce(v_product.name,v_product.title); end if;
      v_name:=coalesce(v_product.name,v_product.title,'Product');
      v_total:=least(v_product.price,coalesce(v_product.discount_price,v_product.sale_price,v_product.price));
      v_subtotal:=v_subtotal+(v_product.price*v_qty); v_grand_total:=v_grand_total+(v_total*v_qty);
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

-- Realtime feeds for customer payment history and seller earnings.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='marketplace_transactions') then execute 'alter publication supabase_realtime add table public.marketplace_transactions'; end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='seller_earnings') then execute 'alter publication supabase_realtime add table public.seller_earnings'; end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='seller_withdrawals') then execute 'alter publication supabase_realtime add table public.seller_withdrawals'; end if;
  end if;
end $$;

-- Allow administrators to reconcile a refund only after confirming the provider-side refund.
drop policy if exists "Administrators update payment transactions" on public.marketplace_transactions;
create policy "Administrators update payment transactions" on public.marketplace_transactions for update to authenticated
using(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'))
with check(exists(select 1 from public.profiles where id=auth.uid() and role='administrator'));
grant update(status,provider_reference,provider_status,failure_reason,updated_at,completed_at) on public.marketplace_transactions to authenticated;
grant select,update on public.marketplace_settings to authenticated;

create or replace function public.reverse_seller_earnings_on_refund()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='refunded' and old.status is distinct from new.status then
   update public.seller_orders o set payment_status='refunded'
   from public.payment_order_allocations a where a.transaction_id=new.id and a.order_id=o.id;
   update public.seller_earnings set status='reversed',updated_at=now()
   where transaction_id=new.id and status<>'withdrawn';
   update public.marketplace_refund_requests set status='refunded',updated_at=now()
   where transaction_id=new.id and status in('approved','processing');
 end if;
 return new;
end;
$$;
drop trigger if exists reverse_seller_earnings_refund_trigger on public.marketplace_transactions;
create trigger reverse_seller_earnings_refund_trigger after update of status on public.marketplace_transactions
for each row execute function public.reverse_seller_earnings_on_refund();

-- Explicit client grants for notification acknowledgements and administrator review actions.
grant update(read_at) on public.marketplace_notifications to authenticated;
grant update(status,processed_at,admin_note) on public.seller_withdrawals to authenticated;
grant update(status,admin_note,updated_at) on public.marketplace_refund_requests to authenticated;
