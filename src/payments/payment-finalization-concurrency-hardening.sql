-- Serialize finalization for transactions that contain the same order(s).
-- This prevents two late/concurrent payment attempts from both passing the
-- duplicate-payment check before either one is marked successful.
create or replace function public.finalize_marketplace_payment(
  p_tx_ref text,
  p_provider_reference text,
  p_amount numeric,
  p_currency text,
  p_provider_status text,
  p_provider_fee numeric default 0
)
returns void
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_tx public.marketplace_transactions%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'Service role required.';
  end if;

  select * into v_tx
  from public.marketplace_transactions
  where tx_ref=p_tx_ref
  for update;

  if not found then
    raise exception 'Unknown transaction reference.';
  end if;

  if v_tx.status='successful' then
    return;
  end if;

  if v_tx.status not in ('pending','expired') then
    raise exception 'Transaction is not eligible for payment finalization.';
  end if;

  if p_provider_status<>'success' or p_currency<>'MWK' or p_amount<>v_tx.amount then
    raise exception 'Provider payment details do not match the expected transaction.';
  end if;

  if coalesce(p_provider_fee,0)<0 then
    raise exception 'Invalid provider fee.';
  end if;

  -- Lock all affected orders in a stable order before checking for another
  -- successful transaction. Competing finalizations for the same order wait.
  perform o.id
  from public.seller_orders o
  join public.payment_order_allocations a on a.order_id=o.id
  where a.transaction_id=v_tx.id
  order by o.id
  for update of o;

  if exists(
    select 1
    from public.payment_order_allocations mine
    join public.payment_order_allocations other on other.order_id=mine.order_id
    join public.marketplace_transactions paid on paid.id=other.transaction_id
    where mine.transaction_id=v_tx.id
      and other.transaction_id<>v_tx.id
      and paid.status='successful'
  ) then
    update public.marketplace_transactions
    set status='refund_pending',
        provider_reference=p_provider_reference,
        provider_status='duplicate_payment_requires_refund',
        provider_fee=coalesce(p_provider_fee,0),
        updated_at=now()
    where id=v_tx.id;

    insert into public.payment_reconciliation(
      transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes
    )
    values(
      v_tx.id,v_tx.tx_ref,p_provider_reference,v_tx.amount,p_amount,p_currency,
      'duplicate_payment',
      'Provider confirmed a second payment for orders already paid by another transaction. Refund this duplicate payment.'
    );

    insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
    values(
      v_tx.customer_id,'duplicate_payment','Duplicate payment under review',
      'A second payment was detected for the same order. The extra payment is flagged for refund review.',
      v_tx.id
    );
    return;
  end if;

  update public.marketplace_transactions
  set status='successful',
      provider_reference=p_provider_reference,
      provider_status=p_provider_status,
      provider_fee=coalesce(p_provider_fee,0),
      completed_at=now(),
      updated_at=now()
  where id=v_tx.id;

  -- Other pending attempts are not rewritten here: each finalizer already
  -- holds its own transaction row, so cross-updating another attempt here
  -- could deadlock against that attempt waiting for the order lock.
  update public.seller_orders o
  set payment_status='paid',
      status=case when o.status='pending' then 'confirmed' else o.status end
  from public.payment_order_allocations a
  where a.transaction_id=v_tx.id and a.order_id=o.id;

  insert into public.seller_earnings(
    seller_id,order_id,transaction_id,gross_amount,platform_fee,net_amount
  )
  select seller_id,order_id,v_tx.id,gross_amount,platform_fee,seller_net
  from public.payment_order_allocations
  where transaction_id=v_tx.id
  on conflict(order_id) do nothing;

  insert into public.payment_reconciliation(
    transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes
  )
  values(
    v_tx.id,v_tx.tx_ref,p_provider_reference,v_tx.amount,p_amount,p_currency,
    'matched','PayChangu verification succeeded.'
  );
end;
$function$;

revoke all on function public.finalize_marketplace_payment(text,text,numeric,text,text,numeric) from public,anon,authenticated;
grant execute on function public.finalize_marketplace_payment(text,text,numeric,text,text,numeric) to service_role;
