create policy "Administrators read payout attempt records" on public.seller_withdrawal_payout_attempts for select to authenticated using (is_active_marketplace_admin());
