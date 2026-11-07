-- Automated seller payout ledger. Apply after payments.sql and withdrawal-payout-hardening.sql.
create table if not exists public.seller_withdrawal_payout_attempts (
  id uuid primary key default gen_random_uuid(),
  withdrawal_id uuid not null unique references public.seller_withdrawals(id) on delete restrict,
  charge_id text not null unique,
  payout_method text not null check (payout_method in ('airtel_money','tnm_mpamba','bank_transfer')),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'MWK' check (currency = 'MWK'),
  status text not null default 'initiating' check (status in ('initiating','pending','unknown','succeeded','failed')),
  provider_reference text,
  provider_status text,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  verified_at timestamptz
);
create unique index if not exists seller_withdrawal_payout_provider_ref_uidx
  on public.seller_withdrawal_payout_attempts(provider_reference)
  where provider_reference is not null and btrim(provider_reference) <> '';
create index if not exists seller_withdrawal_payout_status_idx
  on public.seller_withdrawal_payout_attempts(status, updated_at);

alter table public.seller_withdrawal_payout_attempts enable row level security;
revoke all on public.seller_withdrawal_payout_attempts from anon, authenticated;
grant all on public.seller_withdrawal_payout_attempts to service_role;

create or replace function public.claim_seller_withdrawal_payout(p_withdrawal_id uuid, p_charge_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_withdrawal public.seller_withdrawals%rowtype;
  v_attempt public.seller_withdrawal_payout_attempts%rowtype;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required.'; end if;
  if coalesce(btrim(p_charge_id),'') = '' then raise exception 'A unique payout charge ID is required.'; end if;

  select * into v_withdrawal from public.seller_withdrawals where id=p_withdrawal_id for update;
  if not found then raise exception 'Withdrawal request not found.'; end if;

  select * into v_attempt from public.seller_withdrawal_payout_attempts where withdrawal_id=p_withdrawal_id;
  if found then
    return jsonb_build_object('claimed',false,'attempt_id',v_attempt.id,'charge_id',v_attempt.charge_id,'status',v_attempt.status,'provider_reference',v_attempt.provider_reference);
  end if;

  if v_withdrawal.status not in ('pending','approved') then
    raise exception 'Only pending or approved withdrawals can be submitted for payout.';
  end if;
  if p_charge_id <> v_withdrawal.reference then raise exception 'Payout charge ID must match the unique withdrawal reference.'; end if;

  insert into public.seller_withdrawal_payout_attempts(withdrawal_id,charge_id,payout_method,amount,currency)
  values(v_withdrawal.id,p_charge_id,v_withdrawal.payout_method,v_withdrawal.amount,v_withdrawal.currency)
  returning * into v_attempt;

  update public.seller_withdrawals set status='processing',processed_at=null
  where id=v_withdrawal.id;

  return jsonb_build_object('claimed',true,'attempt_id',v_attempt.id,'charge_id',v_attempt.charge_id,'status',v_attempt.status);
end;
$$;
revoke all on function public.claim_seller_withdrawal_payout(uuid,text) from public, anon, authenticated;
grant execute on function public.claim_seller_withdrawal_payout(uuid,text) to service_role;

create or replace function public.update_seller_withdrawal_payout_attempt(
  p_charge_id text,
  p_status text,
  p_provider_reference text default null,
  p_provider_status text default null,
  p_failure_reason text default null
)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_attempt public.seller_withdrawal_payout_attempts%rowtype;
  v_withdrawal public.seller_withdrawals%rowtype;
  v_provider_ref text := nullif(btrim(p_provider_reference),'');
  v_reason text := left(nullif(btrim(p_failure_reason),''),500);
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required.'; end if;
  if p_status not in ('pending','unknown','succeeded','failed') then raise exception 'Invalid payout attempt status.'; end if;

  select * into v_attempt from public.seller_withdrawal_payout_attempts where charge_id=p_charge_id for update;
  if not found then raise exception 'Payout attempt not found.'; end if;
  select * into v_withdrawal from public.seller_withdrawals where id=v_attempt.withdrawal_id for update;

  if v_attempt.status in ('succeeded','failed') then
    if v_attempt.status <> p_status then raise exception 'A finalized payout attempt cannot change outcome.'; end if;
    return;
  end if;

  update public.seller_withdrawal_payout_attempts
  set status=p_status,
      provider_reference=coalesce(v_provider_ref,provider_reference),
      provider_status=coalesce(nullif(btrim(p_provider_status),''),provider_status),
      failure_reason=case when p_status='failed' then coalesce(v_reason,failure_reason) else failure_reason end,
      updated_at=now(),
      verified_at=case when p_status in ('succeeded','failed') then now() else verified_at end
  where id=v_attempt.id;

  if p_status='succeeded' then
    if v_provider_ref is null and v_attempt.provider_reference is null then
      raise exception 'Verified provider payout reference is required.';
    end if;
    if v_withdrawal.status <> 'processing' then raise exception 'Withdrawal is not processing.'; end if;
    update public.seller_withdrawals
    set status='paid',provider_reference=coalesce(v_provider_ref,v_attempt.provider_reference),processed_at=now()
    where id=v_withdrawal.id;
  elsif p_status='failed' then
    if v_withdrawal.status <> 'processing' then raise exception 'Withdrawal is not processing.'; end if;
    update public.seller_withdrawals set status='failed',processed_at=now()
    where id=v_withdrawal.id;
  end if;
end;
$$;
revoke all on function public.update_seller_withdrawal_payout_attempt(text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.update_seller_withdrawal_payout_attempt(text,text,text,text,text) to service_role;

-- Admins may reject requests, but cannot manually mark a transfer as paid.
create or replace function public.admin_update_seller_withdrawal(
  p_withdrawal_id uuid,
  p_status text,
  p_provider_reference text default null,
  p_admin_note text default null
)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_withdrawal public.seller_withdrawals%rowtype;
  v_note text := nullif(btrim(p_admin_note),'');
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id=auth.uid() and role='administrator' and is_active=true
  ) then raise exception 'Active administrator access required.'; end if;
  if p_status is distinct from 'rejected' then raise exception 'Use Approve & Pay to initiate a provider payout.'; end if;
  if p_provider_reference is not null and btrim(p_provider_reference) <> '' then raise exception 'Provider references are recorded only after provider verification.'; end if;
  if length(coalesce(v_note,'')) > 1000 then raise exception 'Admin note must not exceed 1000 characters.'; end if;

  select * into v_withdrawal from public.seller_withdrawals where id=p_withdrawal_id for update;
  if not found then raise exception 'Withdrawal request not found.'; end if;
  if v_withdrawal.status not in ('pending','approved') then
    raise exception 'Only pending or approved withdrawals can be rejected.';
  end if;

  update public.seller_withdrawals
  set status='rejected',admin_note=v_note,processed_at=now()
  where id=p_withdrawal_id;
end;
$$;
revoke all on function public.admin_update_seller_withdrawal(uuid,text,text,text) from public, anon, service_role;
grant execute on function public.admin_update_seller_withdrawal(uuid,text,text,text) to authenticated;

create or replace function public.notify_seller_withdrawal_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status is distinct from old.status then
    insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
    values(
      new.seller_id,
      'withdrawal_'||new.status,
      'Withdrawal '||new.status,
      case
        when new.status='approved' then 'Your withdrawal request has been approved.'
        when new.status='rejected' then 'Your withdrawal request was rejected.'
        when new.status='processing' then 'Your withdrawal payout has been submitted and is being verified.'
        when new.status='paid' then 'PayChangu has confirmed that your withdrawal was paid.'
        when new.status='failed' then 'PayChangu confirmed that your withdrawal failed. The reserved amount is available again.'
        else 'Your withdrawal status was updated.'
      end,
      new.id
    );
    insert into public.payment_reconciliation(tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes,reconciled_by)
    values(new.reference,new.provider_reference,new.amount,case when new.status='paid' then new.amount else null end,new.currency,'withdrawal_'||new.status,coalesce(new.admin_note,'Withdrawal status changed.'),auth.uid());
  end if;
  return new;
end;
$$;
