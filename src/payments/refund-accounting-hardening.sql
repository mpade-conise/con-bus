-- Refund evidence, controlled administrator actions, and seller recovery audit.
-- Run after payments.sql and delivery/order security migrations.

begin;

create table if not exists public.marketplace_refund_evidence (
  id uuid primary key default gen_random_uuid(),
  refund_request_id uuid references public.marketplace_refund_requests(id) on delete restrict,
  transaction_id uuid references public.marketplace_transactions(id) on delete restrict,
  provider_refund_reference text not null unique,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'MWK' check (currency = 'MWK'),
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check ((refund_request_id is not null) <> (transaction_id is not null))
);

create unique index if not exists marketplace_refund_evidence_request_uidx
  on public.marketplace_refund_evidence(refund_request_id) where refund_request_id is not null;
create unique index if not exists marketplace_refund_evidence_transaction_uidx
  on public.marketplace_refund_evidence(transaction_id) where transaction_id is not null;

create table if not exists public.seller_refund_recoveries (
  id uuid primary key default gen_random_uuid(),
  refund_request_id uuid not null unique references public.marketplace_refund_requests(id) on delete restrict,
  seller_id uuid not null references public.profiles(id) on delete restrict,
  order_id uuid not null references public.seller_orders(id) on delete restrict,
  transaction_id uuid not null references public.marketplace_transactions(id) on delete restrict,
  refund_amount numeric(12,2) not null check (refund_amount > 0),
  seller_recovery_amount numeric(12,2) not null default 0 check (seller_recovery_amount >= 0),
  currency text not null default 'MWK' check (currency = 'MWK'),
  created_at timestamptz not null default now()
);

alter table public.marketplace_refund_evidence enable row level security;
alter table public.seller_refund_recoveries enable row level security;

drop policy if exists "Administrators read marketplace refund evidence" on public.marketplace_refund_evidence;
create policy "Administrators read marketplace refund evidence"
on public.marketplace_refund_evidence for select to authenticated
using (exists(select 1 from public.profiles where id=auth.uid() and role='administrator' and is_active));

drop policy if exists "Administrators read seller refund recoveries" on public.seller_refund_recoveries;
create policy "Administrators read seller refund recoveries"
on public.seller_refund_recoveries for select to authenticated
using (exists(select 1 from public.profiles where id=auth.uid() and role='administrator' and is_active));

revoke all on public.marketplace_refund_evidence from anon, authenticated;
revoke all on public.seller_refund_recoveries from anon, authenticated;
grant select on public.marketplace_refund_evidence, public.seller_refund_recoveries to authenticated;

-- Administrators must use the RPCs below; status changes cannot bypass provider evidence.
revoke update on public.marketplace_refund_requests from authenticated;
revoke update (status, admin_note, updated_at) on public.marketplace_refund_requests from authenticated;

create or replace function public.admin_review_marketplace_refund(
  p_refund_request_id uuid,
  p_status text,
  p_admin_note text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_refund public.marketplace_refund_requests%rowtype;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='administrator' and is_active) then
    raise exception 'Active administrator access required.';
  end if;
  if p_status not in ('approved','rejected','processing') then
    raise exception 'Invalid refund review status.';
  end if;
  select * into v_refund from public.marketplace_refund_requests
  where id=p_refund_request_id for update;
  if not found then raise exception 'Refund request not found.'; end if;
  if not (
    (v_refund.status='requested' and p_status in ('approved','rejected')) or
    (v_refund.status='approved' and p_status='processing')
  ) then
    raise exception 'This refund request cannot move from % to %.',v_refund.status,p_status;
  end if;
  update public.marketplace_refund_requests
  set status=p_status,admin_note=left(coalesce(p_admin_note,'Reviewed by marketplace administrator'),500),updated_at=now()
  where id=v_refund.id;
end;
$$;
revoke all on function public.admin_review_marketplace_refund(uuid,text,text) from public, anon;
grant execute on function public.admin_review_marketplace_refund(uuid,text,text) to authenticated;

create or replace function public.apply_marketplace_refund()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_tx public.marketplace_transactions%rowtype;
  v_earning public.seller_earnings%rowtype;
  v_evidence public.marketplace_refund_evidence%rowtype;
  v_available_before numeric(12,2);
  v_available_after numeric(12,2);
  v_paid_withdrawals numeric(12,2);
  v_recovery numeric(12,2):=0;
  v_refunded numeric(12,2);
begin
  if new.status='refunded' and old.status is distinct from new.status then
    select * into v_evidence from public.marketplace_refund_evidence
    where refund_request_id=new.id and transaction_id is null
      and amount=new.amount and currency='MWK';
    if not found then raise exception 'Verified provider refund evidence is required before confirming this refund.'; end if;

    select * into v_tx from public.marketplace_transactions where id=new.transaction_id for update;
    if not found then raise exception 'Original payment transaction not found.'; end if;
    if v_tx.status not in ('successful','partially_refunded') or v_tx.refunded_amount+new.amount>v_tx.amount then
      raise exception 'Refund exceeds the remaining refundable payment amount.';
    end if;

    select * into v_earning from public.seller_earnings where order_id=new.order_id for update;
    if found then
      if v_earning.status='withdrawn' then
        v_recovery:=v_earning.net_amount;
      elsif v_earning.status='available' then
        select coalesce(sum(net_amount),0) into v_available_before
        from public.seller_earnings where seller_id=new.seller_id and status='available';
        select coalesce(sum(amount),0) into v_paid_withdrawals
        from public.seller_withdrawals where seller_id=new.seller_id and status='paid';
        v_available_after:=greatest(0,v_available_before-v_earning.net_amount);
        v_recovery:=least(v_earning.net_amount,
          greatest(0,v_paid_withdrawals-v_available_after)-greatest(0,v_paid_withdrawals-v_available_before));
      end if;
      update public.seller_earnings
      set status='reversed',updated_at=now()
      where order_id=new.order_id and status in ('pending','available');
    end if;

    update public.seller_orders set payment_status='refunded' where id=new.order_id;
    update public.marketplace_transactions
    set refunded_amount=refunded_amount+new.amount,updated_at=now()
    where id=new.transaction_id returning refunded_amount into v_refunded;
    update public.marketplace_transactions
    set status=case when v_refunded>=amount then 'refunded' else 'partially_refunded' end,
        provider_status='refund_confirmed_with_provider_evidence',updated_at=now()
    where id=new.transaction_id;

    insert into public.seller_refund_recoveries(
      refund_request_id,seller_id,order_id,transaction_id,refund_amount,seller_recovery_amount
    ) values(new.id,new.seller_id,new.order_id,new.transaction_id,new.amount,v_recovery);

    insert into public.payment_reconciliation(
      transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes,reconciled_by
    ) values(
      new.transaction_id,v_tx.tx_ref,v_evidence.provider_refund_reference,new.amount,new.amount,'MWK',
      'refund_confirmed','Provider refund reference recorded and amount matched; seller recovery amount: '||v_recovery||' MWK.',auth.uid()
    );

    insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
    values(new.customer_id,'refund_confirmed','Refund confirmed','Your refund has been recorded with provider refund evidence.',new.id);
    insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
    values(new.seller_id,'seller_refund_confirmed','Customer refund confirmed',
      case when v_recovery>0 then 'A refund was confirmed. '||v_recovery||' MWK of seller earnings requires recovery through future earnings.' else 'A refund was confirmed and the related seller earnings were reversed.' end,new.id);
  end if;
  return new;
end;
$$;

revoke all on function public.apply_marketplace_refund() from public, anon, authenticated, service_role;

create or replace function public.admin_confirm_marketplace_refund(
  p_refund_request_id uuid,
  p_provider_refund_reference text,
  p_provider_refund_amount numeric
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_refund public.marketplace_refund_requests%rowtype;
  v_tx public.marketplace_transactions%rowtype;
  v_reference text:=nullif(trim(p_provider_refund_reference),'');
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='administrator' and is_active) then
    raise exception 'Active administrator access required.';
  end if;
  if v_reference is null or length(v_reference)>200 then
    raise exception 'Enter a valid provider refund reference.';
  end if;
  select * into v_refund from public.marketplace_refund_requests
  where id=p_refund_request_id for update;
  if not found or v_refund.status not in ('approved','processing') then
    raise exception 'Only approved or processing refund requests can be confirmed.';
  end if;
  if p_provider_refund_amount is null or p_provider_refund_amount<>v_refund.amount then
    raise exception 'Provider refund amount must exactly match the requested refund amount.';
  end if;
  select * into v_tx from public.marketplace_transactions where id=v_refund.transaction_id for update;
  if not found or v_tx.status not in ('successful','partially_refunded')
     or v_tx.refunded_amount+v_refund.amount>v_tx.amount then
    raise exception 'Refund exceeds the remaining refundable payment amount.';
  end if;
  insert into public.marketplace_refund_evidence(
    refund_request_id,provider_refund_reference,amount,currency,recorded_by
  ) values(v_refund.id,v_reference,p_provider_refund_amount,'MWK',auth.uid());
  update public.marketplace_refund_requests
  set status='refunded',admin_note='Provider refund reference: '||v_reference,updated_at=now()
  where id=v_refund.id;
end;
$$;
revoke all on function public.admin_confirm_marketplace_refund(uuid,text,numeric) from public, anon;
grant execute on function public.admin_confirm_marketplace_refund(uuid,text,numeric) to authenticated;

-- Duplicate-payment refunds use the same globally unique provider evidence registry.
create or replace function public.admin_confirm_duplicate_payment_refund(
  p_tx_ref text,
  p_provider_refund_reference text,
  p_provider_refund_amount numeric
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_tx public.marketplace_transactions%rowtype;
  v_reference text:=nullif(trim(p_provider_refund_reference),'');
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='administrator' and is_active) then
    raise exception 'Active administrator access required.';
  end if;
  if v_reference is null or length(v_reference)>200 then
    raise exception 'Enter a valid provider refund reference.';
  end if;
  select * into v_tx from public.marketplace_transactions where tx_ref=p_tx_ref for update;
  if not found or v_tx.status<>'refund_pending' then
    raise exception 'This transaction is not awaiting duplicate-payment refund confirmation.';
  end if;
  if p_provider_refund_amount is null or p_provider_refund_amount<>v_tx.amount then
    raise exception 'Provider refund amount must exactly match the duplicate payment amount.';
  end if;
  insert into public.marketplace_refund_evidence(
    transaction_id,provider_refund_reference,amount,currency,recorded_by
  ) values(v_tx.id,v_reference,p_provider_refund_amount,'MWK',auth.uid());
  update public.marketplace_transactions
  set status='refunded',refunded_amount=amount,provider_status='duplicate_refund_confirmed_with_provider_evidence',
      updated_at=now(),completed_at=now()
  where id=v_tx.id;
  insert into public.payment_reconciliation(
    transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes,reconciled_by
  ) values(
    v_tx.id,v_tx.tx_ref,v_reference,v_tx.amount,p_provider_refund_amount,'MWK',
    'duplicate_refund_confirmed','Duplicate payment refund recorded with provider refund evidence.',auth.uid()
  );
end;
$$;
revoke all on function public.admin_confirm_duplicate_payment_refund(text) from public, anon, authenticated, service_role;
revoke all on function public.admin_confirm_duplicate_payment_refund(text,text,numeric) from public, anon;
grant execute on function public.admin_confirm_duplicate_payment_refund(text,text,numeric) to authenticated;

commit;
