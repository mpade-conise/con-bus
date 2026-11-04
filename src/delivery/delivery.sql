-- Delivery and shipping management. Run after orders.sql and payments.sql.
create extension if not exists pgcrypto;
create table if not exists public.customer_delivery_addresses(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.profiles(id) on delete cascade,label text not null default 'Home',recipient_name text not null,phone text not null,city text not null,district text,address text not null,instructions text,is_default boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index if not exists customer_delivery_addresses_owner_idx on public.customer_delivery_addresses(customer_id,created_at desc);
alter table public.customer_delivery_addresses enable row level security;
drop policy if exists "Customers manage own delivery addresses" on public.customer_delivery_addresses;
create policy "Customers manage own delivery addresses" on public.customer_delivery_addresses for all to authenticated using(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='customer' and is_active)) with check(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='customer' and is_active));
grant select,insert,update,delete on public.customer_delivery_addresses to authenticated;

create table if not exists public.seller_delivery_settings(seller_id uuid primary key references public.profiles(id) on delete cascade,home_delivery_enabled boolean not null default true,pickup_enabled boolean not null default true,pickup_location text,pickup_instructions text,default_min_days integer not null default 1 check(default_min_days between 0 and 90),default_max_days integer not null default 3 check(default_max_days between default_min_days and 90),updated_at timestamptz not null default now());
alter table public.seller_delivery_settings enable row level security;
drop policy if exists "Sellers manage own delivery settings" on public.seller_delivery_settings;
create policy "Sellers manage own delivery settings" on public.seller_delivery_settings for all to authenticated using(seller_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='seller' and is_active)) with check(seller_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='seller' and is_active));
drop policy if exists "Customers view seller delivery settings" on public.seller_delivery_settings;\ncreate policy "Customers view seller delivery settings" on public.seller_delivery_settings for select to authenticated using(true);\ngrant select,insert,update,delete on public.seller_delivery_settings to authenticated;

create table if not exists public.seller_delivery_zones(id uuid primary key default gen_random_uuid(),seller_id uuid not null references public.profiles(id) on delete cascade,zone_name text not null,city text not null,district text,delivery_fee numeric(12,2) not null default 0 check(delivery_fee>=0),min_days integer not null default 1 check(min_days between 0 and 90),max_days integer not null default 3 check(max_days between min_days and 90),is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(seller_id,zone_name));
create index if not exists seller_delivery_zones_lookup_idx on public.seller_delivery_zones(seller_id,city,district) where is_active;
alter table public.seller_delivery_zones enable row level security;
drop policy if exists "Customers view active delivery zones" on public.seller_delivery_zones;
create policy "Customers view active delivery zones" on public.seller_delivery_zones for select to authenticated using(is_active);
drop policy if exists "Sellers manage own delivery zones" on public.seller_delivery_zones;
create policy "Sellers manage own delivery zones" on public.seller_delivery_zones for all to authenticated using(seller_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='seller' and is_active)) with check(seller_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='seller' and is_active));
grant select,insert,update,delete on public.seller_delivery_zones to authenticated;

create table if not exists public.seller_delivery_personnel(id uuid primary key default gen_random_uuid(),seller_id uuid not null references public.profiles(id) on delete cascade,full_name text not null,phone text not null,vehicle text,notes text,is_active boolean not null default true,created_at timestamptz not null default now(),unique(seller_id,phone));
alter table public.seller_delivery_personnel enable row level security;
drop policy if exists "Sellers manage own delivery personnel" on public.seller_delivery_personnel;
create policy "Sellers manage own delivery personnel" on public.seller_delivery_personnel for all to authenticated using(seller_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='seller' and is_active)) with check(seller_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='seller' and is_active));
grant select,insert,update,delete on public.seller_delivery_personnel to authenticated;

alter table public.seller_orders add column if not exists delivery_status text not null default 'pending',add column if not exists tracking_number text,add column if not exists delivery_zone_id uuid references public.seller_delivery_zones(id) on delete set null,add column if not exists delivery_person_id uuid references public.seller_delivery_personnel(id) on delete set null,add column if not exists estimated_delivery_at timestamptz,add column if not exists delivered_at timestamptz,add column if not exists pickup_location text,add column if not exists delivery_instructions text;
alter table public.seller_orders drop constraint if exists seller_orders_delivery_status_check;
alter table public.seller_orders add constraint seller_orders_delivery_status_check check(delivery_status in('pending','preparing','assigned','picked_up','in_transit','ready_for_pickup','delivered','collected','failed'));
grant update(delivery_status,tracking_number,delivery_zone_id,delivery_person_id,estimated_delivery_at,delivered_at,pickup_location,delivery_instructions) on public.seller_orders to authenticated;

create table if not exists public.seller_delivery_assignments(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.seller_orders(id) on delete cascade,seller_id uuid not null references public.profiles(id) on delete cascade,personnel_id uuid not null references public.seller_delivery_personnel(id) on delete restrict,assigned_by uuid references public.profiles(id) on delete set null,assigned_at timestamptz not null default now(),unassigned_at timestamptz,notes text);
create index if not exists seller_delivery_assignments_order_idx on public.seller_delivery_assignments(order_id,assigned_at desc);
alter table public.seller_delivery_assignments enable row level security;
drop policy if exists "Sellers read own delivery assignments" on public.seller_delivery_assignments;
create policy "Sellers read own delivery assignments" on public.seller_delivery_assignments for select to authenticated using(seller_id=auth.uid());
grant select on public.seller_delivery_assignments to authenticated;

create or replace function public.place_marketplace_order_with_delivery(p_items jsonb,p_delivery_address jsonb,p_delivery_method text,p_payment_method text,p_customer_note text default null,p_delivery_zones jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_orders jsonb;v_order jsonb;v_final jsonb:='[]'::jsonb;v_zone_id uuid;v_zone public.seller_delivery_zones%rowtype;v_settings public.seller_delivery_settings%rowtype;v_fee numeric(12,2);v_eta timestamptz;v_location text;
begin
 if p_delivery_method not in('home_delivery','pickup') then raise exception 'Choose home delivery or pickup.';end if;
 v_orders:=public.place_marketplace_order(p_items,p_delivery_address,p_delivery_method,p_payment_method,p_customer_note);
 for v_order in select value from jsonb_array_elements(v_orders) loop
  select * into v_settings from public.seller_delivery_settings where seller_id=(v_order->>'seller_id')::uuid;
  if not found then v_settings.seller_id:=(v_order->>'seller_id')::uuid;v_settings.home_delivery_enabled:=true;v_settings.pickup_enabled:=true;v_settings.pickup_location:=null;v_settings.default_min_days:=1;v_settings.default_max_days:=3;end if;
  v_fee:=0;v_eta:=null;v_zone_id:=null;v_location:=null;
  if p_delivery_method='home_delivery' then
   if not v_settings.home_delivery_enabled then raise exception 'This seller does not currently offer home delivery.';end if;
   v_zone_id:=nullif(p_delivery_zones->>(v_order->>'seller_id'),'')::uuid;
   if v_zone_id is null then raise exception 'Select a delivery zone for every seller in your cart.';end if;
   select * into v_zone from public.seller_delivery_zones where id=v_zone_id and seller_id=(v_order->>'seller_id')::uuid and is_active;
   if not found then raise exception 'A selected delivery zone is no longer available.';end if;
   if lower(v_zone.city)<>lower(coalesce(p_delivery_address->>'city','')) then raise exception 'The selected delivery zone does not match the delivery city.';end if;
   if coalesce(v_zone.district,'')<>'' and lower(v_zone.district)<>lower(coalesce(p_delivery_address->>'region',p_delivery_address->>'district','')) then raise exception 'The selected delivery zone does not match the delivery district.';end if;
   v_fee:=v_zone.delivery_fee;v_eta:=now()+make_interval(days=>ceil((v_zone.min_days+v_zone.max_days)::numeric/2)::integer);
  else
   if not v_settings.pickup_enabled then raise exception 'This seller does not currently offer pickup.';end if;
   v_location:=v_settings.pickup_location;v_eta:=now()+make_interval(days=>ceil((v_settings.default_min_days+v_settings.default_max_days)::numeric/2)::integer);
  end if;
  update public.seller_orders set shipping_amount=v_fee,total_amount=total_amount+v_fee,delivery_zone_id=v_zone_id,delivery_status=case when p_delivery_method='pickup' then 'ready_for_pickup' else 'pending' end,estimated_delivery_at=v_eta,pickup_location=v_location,delivery_instructions=nullif(p_delivery_address->>'instructions','') where id=(v_order->>'id')::uuid;
  insert into public.seller_order_events(order_id,actor_id,event_type,note) values((v_order->>'id')::uuid,auth.uid(),'delivery_configured',case when p_delivery_method='pickup' then 'Pickup selected'||coalesce(': '||v_location,'') else 'Home delivery zone: '||v_zone.zone_name||'; fee MWK '||v_fee end);
  v_final:=v_final||jsonb_build_array(v_order||jsonb_build_object('delivery_fee',v_fee,'total_amount',(v_order->>'total_amount')::numeric+v_fee,'estimated_delivery_at',v_eta));
 end loop;
 return v_final;
end;$$;
revoke all on function public.place_marketplace_order_with_delivery(jsonb,jsonb,text,text,text,jsonb) from public,anon;
grant execute on function public.place_marketplace_order_with_delivery(jsonb,jsonb,text,text,text,jsonb) to authenticated;\nrevoke execute on function public.place_marketplace_order(jsonb,jsonb,text,text,text) from authenticated;

create or replace function public.update_seller_delivery(p_order_id uuid,p_delivery_status text,p_tracking_number text default null,p_personnel_id uuid default null,p_estimated_delivery_at timestamptz default null,p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.seller_orders%rowtype;v_person public.seller_delivery_personnel%rowtype;v_old text;
begin
 select * into v_order from public.seller_orders where id=p_order_id and seller_id=auth.uid() for update;
 if not found then raise exception 'Order not found for this seller.';end if;
 if p_delivery_status not in('pending','preparing','assigned','picked_up','in_transit','ready_for_pickup','delivered','collected','failed') then raise exception 'Invalid delivery status.';end if;
 if p_personnel_id is not null then select * into v_person from public.seller_delivery_personnel where id=p_personnel_id and seller_id=auth.uid() and is_active;if not found then raise exception 'Select an active delivery person from your own team.';end if;end if;
 if p_delivery_status in('assigned','picked_up','in_transit') and v_order.delivery_method='home_delivery' and p_personnel_id is null and v_order.delivery_person_id is null then raise exception 'Assign a delivery person before dispatch.';end if;
 if p_delivery_status in('delivered','collected') then
  if v_order.status not in('ready_for_delivery','shipped') then raise exception 'The order must be ready for dispatch before delivery can be completed.';end if;
  if p_delivery_status='delivered' and v_order.delivery_method<>'home_delivery' then raise exception 'Use collected to complete a pickup order.';end if;
  if p_delivery_status='collected' and v_order.delivery_method<>'pickup' then raise exception 'Use delivered to complete a home delivery order.';end if;
  if v_order.status='ready_for_delivery' then update public.seller_orders set status='shipped' where id=p_order_id;end if;
  if (select status from public.seller_orders where id=p_order_id)='shipped' then update public.seller_orders set status='delivered' where id=p_order_id;end if;
 end if;
 if p_delivery_status='in_transit' and v_order.status not in('ready_for_delivery','shipped') then raise exception 'The order must be ready for dispatch before it can be sent.';end if;
 if p_delivery_status='in_transit' and v_order.status='ready_for_delivery' then update public.seller_orders set status='shipped' where id=p_order_id;end if;
 if p_delivery_status='ready_for_pickup' and (v_order.delivery_method<>'pickup' or v_order.status not in('processing','ready_for_delivery')) then raise exception 'This pickup order is not ready for collection.';end if;
 v_old:=v_order.delivery_status;
 update public.seller_orders set delivery_status=p_delivery_status,tracking_number=coalesce(nullif(trim(p_tracking_number),''),tracking_number),delivery_person_id=coalesce(p_personnel_id,delivery_person_id),estimated_delivery_at=coalesce(p_estimated_delivery_at,estimated_delivery_at),delivered_at=case when p_delivery_status in('delivered','collected') then now() else delivered_at end where id=p_order_id;
 if p_personnel_id is not null then insert into public.seller_delivery_assignments(order_id,seller_id,personnel_id,assigned_by,notes) values(p_order_id,auth.uid(),p_personnel_id,auth.uid(),nullif(p_note,''));end if;
 insert into public.seller_order_events(order_id,actor_id,event_type,old_status,new_status,note) values(p_order_id,auth.uid(),'delivery_status_changed',v_old,p_delivery_status,coalesce(nullif(p_note,''),'Delivery status updated')||case when p_tracking_number is not null then '; tracking: '||p_tracking_number else '' end);
end;$$;
revoke all on function public.update_seller_delivery(uuid,text,text,uuid,timestamptz,text) from public,anon;
grant execute on function public.update_seller_delivery(uuid,text,text,uuid,timestamptz,text) to authenticated;

create or replace function public.confirm_marketplace_delivery(p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.seller_orders%rowtype;
begin
 select * into v_order from public.seller_orders where id=p_order_id and customer_id=auth.uid() for update;
 if not found then raise exception 'Order not found.';end if;
 if v_order.delivery_method='pickup' then
  if v_order.status<>'ready_for_delivery' or v_order.delivery_status<>'ready_for_pickup' then raise exception 'This pickup order is not ready for collection confirmation.';end if;
  update public.seller_orders set status='shipped' where id=p_order_id;
  update public.seller_orders set status='delivered',delivery_status='collected',delivered_at=now() where id=p_order_id;
  insert into public.seller_order_events(order_id,actor_id,event_type,note) values(p_order_id,auth.uid(),'customer_pickup_confirmed','Customer confirmed collection of the order.');
 else
  if v_order.status<>'shipped' or v_order.delivery_status not in('in_transit','delivered') then raise exception 'This order is not awaiting delivery confirmation.';end if;
  update public.seller_orders set status='delivered',delivery_status='delivered',delivered_at=coalesce(delivered_at,now()) where id=p_order_id;
  insert into public.seller_order_events(order_id,actor_id,event_type,note) values(p_order_id,auth.uid(),'customer_delivery_confirmed','Customer confirmed receipt of the order.');
 end if;
end;$$;
revoke all on function public.confirm_marketplace_delivery(uuid) from public,anon;
grant execute on function public.confirm_marketplace_delivery(uuid) to authenticated;

do $$ begin if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='seller_delivery_zones') then execute 'alter publication supabase_realtime add table public.seller_delivery_zones';end if;end $$;
