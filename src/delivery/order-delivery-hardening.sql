-- Run after the existing orders.sql, payments.sql and delivery.sql migrations.
-- Restricts seller order writes and makes customer confirmation the only normal earnings-release path.
begin;

-- Remove direct client writes, including any historical column-level grants.
revoke all privileges on table public.seller_orders from anon, authenticated;
do $$
declare c record;
begin
  for c in
    select column_name from information_schema.columns
    where table_schema='public' and table_name='seller_orders'
  loop
    execute format('revoke insert (%I), update (%I), references (%I) on table public.seller_orders from anon, authenticated',c.column_name,c.column_name,c.column_name);
  end loop;
end $$;
grant select on table public.seller_orders to authenticated;
drop policy if exists "Sellers update own order status" on public.seller_orders;

-- Sellers may advance fulfilment only through this ownership-checked RPC.
create or replace function public.update_seller_order_status(
  p_order_id uuid,
  p_status text,
  p_cancellation_reason text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); v_order public.seller_orders%rowtype;
begin
  if v_uid is null or coalesce(auth.role(),'')<>'authenticated' then raise exception 'Sign in required.'; end if;
  if not exists(select 1 from public.profiles where id=v_uid and role='seller' and is_active) then
    raise exception 'An active seller account is required.';
  end if;
  select * into v_order from public.seller_orders where id=p_order_id and seller_id=v_uid for update;
  if not found then raise exception 'Order not found for this seller.'; end if;
  if p_status not in('confirmed','processing','ready_for_delivery','shipped','cancelled') then
    raise exception 'This status can only be set through the customer confirmation or administrator workflow.';
  end if;
  if not (
    (v_order.status='pending' and p_status in('confirmed','cancelled')) or
    (v_order.status='confirmed' and p_status in('processing','cancelled')) or
    (v_order.status='processing' and p_status in('ready_for_delivery','cancelled')) or
    (v_order.status='ready_for_delivery' and p_status in('shipped','cancelled'))
  ) then raise exception 'This order status transition is not allowed.'; end if;
  update public.seller_orders
  set status=p_status,
      cancellation_reason=case when p_status='cancelled' then coalesce(nullif(trim(p_cancellation_reason),''),'Cancelled by seller') else cancellation_reason end
  where id=p_order_id;
end;
$$;
revoke all on function public.update_seller_order_status(uuid,text,text) from public,anon;
grant execute on function public.update_seller_order_status(uuid,text,text) to authenticated;

-- A delivered order can only be confirmed by its customer (or a trusted service).
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
    if new.status='delivered'
      and not (
        coalesce(auth.role(),'')='service_role'
        or (coalesce(auth.role(),'')='authenticated' and auth.uid()=old.customer_id)
      ) then
      raise exception 'Only the customer can confirm receipt of this order.';
    end if;
  end if;
  return new;
end;
$$;

-- Seller delivery updates are reports only. They never set order.status=delivered
-- and never set delivered_at; the customer confirmation RPC does that.
create or replace function public.update_seller_delivery(
  p_order_id uuid,
  p_delivery_status text,
  p_tracking_number text default null,
  p_personnel_id uuid default null,
  p_estimated_delivery_at timestamptz default null,
  p_note text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_order public.seller_orders%rowtype;
  v_person public.seller_delivery_personnel%rowtype;
  v_old text;
begin
  if v_uid is null or coalesce(auth.role(),'')<>'authenticated'
    or not exists(select 1 from public.profiles where id=v_uid and role='seller' and is_active) then
    raise exception 'An active seller account is required.';
  end if;
  select * into v_order from public.seller_orders where id=p_order_id and seller_id=v_uid for update;
  if not found then raise exception 'Order not found for this seller.'; end if;
  if p_delivery_status not in('pending','preparing','assigned','picked_up','in_transit','ready_for_pickup','delivered','collected','failed') then
    raise exception 'Invalid delivery status.';
  end if;
  if p_personnel_id is not null then
    select * into v_person from public.seller_delivery_personnel
    where id=p_personnel_id and seller_id=v_uid and is_active;
    if not found then raise exception 'Select an active delivery person from your own team.'; end if;
  end if;
  if p_delivery_status in('ready_for_pickup','picked_up','in_transit','delivered','collected')
    and v_order.payment_method<>'cash_on_delivery' and v_order.payment_status<>'paid' then
    raise exception 'Payment must be verified before the order is dispatched or collected.';
  end if;
  if p_delivery_status in('assigned','picked_up','in_transit')
    and v_order.delivery_method='home_delivery'
    and p_personnel_id is null and v_order.delivery_person_id is null then
    raise exception 'Assign a delivery person before dispatch.';
  end if;
  if p_delivery_status in('delivered','in_transit','picked_up') and v_order.delivery_method<>'home_delivery'
    and p_delivery_status<>'delivered' then
    raise exception 'Courier dispatch statuses apply only to home delivery orders.';
  end if;
  if p_delivery_status='delivered' and v_order.delivery_method<>'home_delivery' then
    raise exception 'Use collected to report a pickup collection.';
  end if;
  if p_delivery_status='collected' and v_order.delivery_method<>'pickup' then
    raise exception 'Use delivered to report a home delivery.';
  end if;
  if p_delivery_status in('delivered','collected','picked_up','in_transit')
    and v_order.status not in('ready_for_delivery','shipped') then
    raise exception 'The order must be ready for dispatch before this delivery update.';
  end if;
  if p_delivery_status in('picked_up','in_transit','delivered') and v_order.status='ready_for_delivery' then
    update public.seller_orders set status='shipped' where id=p_order_id;
  end if;
  if p_delivery_status='ready_for_pickup' then
    if v_order.delivery_method<>'pickup' or v_order.status not in('processing','ready_for_delivery') then
      raise exception 'This pickup order is not ready for collection.';
    end if;
    if v_order.status='processing' then
      update public.seller_orders set status='ready_for_delivery' where id=p_order_id;
    end if;
  end if;
  v_old:=v_order.delivery_status;
  update public.seller_orders
  set delivery_status=p_delivery_status,
      tracking_number=coalesce(nullif(trim(p_tracking_number),''),tracking_number),
      delivery_person_id=coalesce(p_personnel_id,delivery_person_id),
      estimated_delivery_at=coalesce(p_estimated_delivery_at,estimated_delivery_at)
  where id=p_order_id;
  if p_personnel_id is not null then
    insert into public.seller_delivery_assignments(order_id,seller_id,personnel_id,assigned_by,notes)
    values(p_order_id,v_uid,p_personnel_id,v_uid,nullif(p_note,''));
  end if;
  insert into public.seller_order_events(order_id,actor_id,event_type,old_status,new_status,note)
  values(p_order_id,v_uid,'delivery_status_changed',v_old,p_delivery_status,
    coalesce(nullif(p_note,''),'Delivery status updated')||
    case when p_tracking_number is not null then '; tracking: '||p_tracking_number else '' end);
end;
$$;
revoke all on function public.update_seller_delivery(uuid,text,text,uuid,timestamptz,text) from public,anon;
grant execute on function public.update_seller_delivery(uuid,text,text,uuid,timestamptz,text) to authenticated;

-- Customer-only confirmation; this is the only normal route that releases earnings.
create or replace function public.confirm_marketplace_delivery(p_order_id uuid)
returns void
language plpgsql security definer set search_path=public as $$
declare v_order public.seller_orders%rowtype; v_uid uuid:=auth.uid();
begin
  if v_uid is null or coalesce(auth.role(),'')<>'authenticated'
    or not exists(select 1 from public.profiles where id=v_uid and role='customer' and is_active) then
    raise exception 'An active customer account is required.';
  end if;
  select * into v_order from public.seller_orders where id=p_order_id and customer_id=v_uid for update;
  if not found then raise exception 'Order not found.'; end if;
  if v_order.payment_method<>'cash_on_delivery' and v_order.payment_status<>'paid' then
    raise exception 'Payment must be verified before confirming receipt.';
  end if;
  if v_order.delivery_method='pickup' then
    if v_order.status not in('ready_for_delivery','shipped')
      or v_order.delivery_status not in('ready_for_pickup','collected') then
      raise exception 'This pickup order is not awaiting collection confirmation.';
    end if;
    update public.seller_orders
    set status='delivered',delivery_status='collected',delivered_at=coalesce(delivered_at,now())
    where id=p_order_id;
    insert into public.seller_order_events(order_id,actor_id,event_type,note)
    values(p_order_id,v_uid,'customer_pickup_confirmed','Customer confirmed collection of the order.');
  else
    if v_order.status<>'shipped' or v_order.delivery_status not in('in_transit','delivered') then
      raise exception 'This order is not awaiting delivery confirmation.';
    end if;
    update public.seller_orders
    set status='delivered',delivery_status='delivered',delivered_at=coalesce(delivered_at,now())
    where id=p_order_id;
    insert into public.seller_order_events(order_id,actor_id,event_type,note)
    values(p_order_id,v_uid,'customer_delivery_confirmed','Customer confirmed receipt of the order.');
  end if;
end;
$$;
revoke all on function public.confirm_marketplace_delivery(uuid) from public,anon;
grant execute on function public.confirm_marketplace_delivery(uuid) to authenticated;

-- Defense in depth: even an unexpected status update cannot release earnings
-- unless the actor is the customer who owns the order or the trusted service role.
create or replace function public.release_seller_earnings_on_delivery()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='delivered' and old.status is distinct from new.status
    and (
      coalesce(auth.role(),'')='service_role'
      or (coalesce(auth.role(),'')='authenticated' and auth.uid()=new.customer_id)
    ) then
    update public.seller_earnings
    set status='available',available_at=now(),updated_at=now()
    where order_id=new.id and status='pending';
  end if;
  return new;
end;
$$;

commit;
