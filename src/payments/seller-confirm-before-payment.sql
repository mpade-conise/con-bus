-- Seller confirmation is the prerequisite for online payment.
-- Customers see Pay Now only after the seller moves the order to confirmed.

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
  if (select count(*) from public.seller_orders where id=any(p_order_ids) and customer_id=v_uid and status='confirmed' and payment_status in('pending','failed'))<>array_length(p_order_ids,1) then raise exception 'Payment is available only after the seller confirms the order.'; end if;
  update public.marketplace_transactions t set status='expired',updated_at=now()
  where t.status='pending' and t.created_at<now()-interval '30 minutes' and exists(select 1 from public.payment_order_allocations a where a.transaction_id=t.id and a.order_id=any(p_order_ids));
  if exists(select 1 from public.marketplace_transactions t join public.payment_order_allocations a on a.transaction_id=t.id where t.status='pending' and a.order_id=any(p_order_ids)) then raise exception 'A payment is already in progress for this order. Wait for its result before retrying.'; end if;
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
