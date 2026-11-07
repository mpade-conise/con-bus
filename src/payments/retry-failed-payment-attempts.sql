-- Keep failed/expired PayChangu attempts retryable without reopening paid orders.
-- A pending attempt is only changed after PayChangu has reported a definitive failure.
create or replace function public.fail_marketplace_payment(p_tx_ref text,p_reason text)
returns void
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_tx public.marketplace_transactions%rowtype;
  v_changed boolean:=false;
  v_reason text:=left(coalesce(nullif(btrim(p_reason),''),'Payment failed'),500);
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Service role required.';
  end if;

  select * into v_tx
  from public.marketplace_transactions
  where tx_ref=p_tx_ref
  for update;

  if not found then return; end if;

  if v_tx.status in ('pending','expired') then
    update public.marketplace_transactions
    set status='failed',failure_reason=v_reason,updated_at=now()
    where id=v_tx.id;
    v_changed:=true;
  elsif v_tx.status<>'failed' then
    return;
  end if;

  -- Synchronize order state for retries, but never downgrade an order that
  -- has already been paid by this or another successful transaction.
  update public.seller_orders o
  set payment_status='failed'
  from public.payment_order_allocations a
  where a.transaction_id=v_tx.id
    and a.order_id=o.id
    and o.payment_status not in ('paid','refunded')
    and not exists(
      select 1
      from public.payment_order_allocations other_a
      join public.marketplace_transactions paid on paid.id=other_a.transaction_id
      where other_a.order_id=o.id
        and paid.status in ('successful','refund_pending','partially_refunded','refunded')
    );

  if v_changed then
    insert into public.payment_reconciliation(transaction_id,tx_ref,expected_amount,currency,result,notes)
    values(v_tx.id,v_tx.tx_ref,v_tx.amount,v_tx.currency,'failed',v_reason);
  end if;
end;
$function$;

revoke all on function public.fail_marketplace_payment(text,text) from public,anon,authenticated;
grant execute on function public.fail_marketplace_payment(text,text) to service_role;
