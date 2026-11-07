-- Allow definitive PayChangu failure results to close expired transactions too.
-- Keep this transition idempotent and preserve already-paid orders.
create or replace function public.fail_marketplace_payment(p_tx_ref text,p_reason text)
returns void
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_tx public.marketplace_transactions%rowtype;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Service role required.';
  end if;

  select * into v_tx
  from public.marketplace_transactions
  where tx_ref=p_tx_ref
  for update;

  if not found or v_tx.status not in ('pending','expired') then
    return;
  end if;

  update public.marketplace_transactions
  set status='failed',
      failure_reason=left(coalesce(nullif(btrim(p_reason),''),'Payment failed'),500),
      updated_at=now()
  where id=v_tx.id;

  update public.seller_orders o
  set payment_status='failed'
  from public.payment_order_allocations a
  where a.transaction_id=v_tx.id
    and a.order_id=o.id
    and o.payment_status<>'paid';

  insert into public.payment_reconciliation(transaction_id,tx_ref,expected_amount,currency,result,notes)
  values(v_tx.id,v_tx.tx_ref,v_tx.amount,v_tx.currency,'failed',
    left(coalesce(nullif(btrim(p_reason),''),'Payment failed'),500));
end;
$function$;

revoke all on function public.fail_marketplace_payment(text,text) from public,anon,authenticated;
grant execute on function public.fail_marketplace_payment(text,text) to service_role;
