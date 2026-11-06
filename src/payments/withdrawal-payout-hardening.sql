-- Secure seller payout state changes. Apply after payments.sql.
create unique index if not exists seller_withdrawals_provider_reference_uidx
on public.seller_withdrawals (provider_reference)
where provider_reference is not null and btrim(provider_reference) <> '';

drop policy if exists "Administrators manage withdrawals" on public.seller_withdrawals;
drop policy if exists "Administrators read withdrawals" on public.seller_withdrawals;
create policy "Administrators read withdrawals"
on public.seller_withdrawals for select to authenticated
using (exists (
  select 1 from public.profiles p
  where p.id = auth.uid() and p.role = 'administrator' and p.is_active = true
));

revoke all on public.seller_withdrawals from anon, authenticated;
grant select on public.seller_withdrawals to authenticated;

create or replace function public.admin_update_seller_withdrawal(
  p_withdrawal_id uuid,
  p_status text,
  p_provider_reference text default null,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_withdrawal public.seller_withdrawals%rowtype;
  v_reference text := nullif(btrim(p_provider_reference), '');
  v_note text := nullif(btrim(p_admin_note), '');
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'administrator' and is_active = true
  ) then
    raise exception 'Active administrator access required.';
  end if;

  if p_status not in ('approved', 'rejected', 'processing', 'paid', 'failed') then
    raise exception 'Invalid withdrawal status.';
  end if;
  if length(coalesce(v_note, '')) > 1000 then
    raise exception 'Admin note must not exceed 1000 characters.';
  end if;

  select * into v_withdrawal
  from public.seller_withdrawals
  where id = p_withdrawal_id
  for update;

  if not found then
    raise exception 'Withdrawal request not found.';
  end if;

  if not (
    (v_withdrawal.status = 'pending' and p_status in ('approved', 'rejected')) or
    (v_withdrawal.status = 'approved' and p_status in ('processing', 'rejected')) or
    (v_withdrawal.status = 'processing' and p_status in ('paid', 'failed'))
  ) then
    raise exception 'Withdrawal transition from % to % is not allowed.', v_withdrawal.status, p_status;
  end if;

  if p_status = 'paid' and v_reference is null then
    raise exception 'A verified provider payout reference is required before marking a withdrawal as paid.';
  end if;
  if p_status <> 'paid' and v_reference is not null then
    raise exception 'Provider payout reference can only be recorded when confirming payment.';
  end if;

  update public.seller_withdrawals
  set status = p_status,
      provider_reference = case when p_status = 'paid' then v_reference else provider_reference end,
      admin_note = v_note,
      processed_at = case when p_status in ('paid', 'rejected', 'failed') then now() else null end
  where id = p_withdrawal_id;
end;
$function$;

revoke all on function public.admin_update_seller_withdrawal(uuid, text, text, text) from public;
revoke all on function public.admin_update_seller_withdrawal(uuid, text, text, text) from anon;
revoke all on function public.admin_update_seller_withdrawal(uuid, text, text, text) from service_role;
grant execute on function public.admin_update_seller_withdrawal(uuid, text, text, text) to authenticated;
