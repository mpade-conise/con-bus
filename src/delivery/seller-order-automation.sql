-- Seller-controlled automatic order preparation.
-- Run this migration after delivery.sql and order-delivery-hardening.sql.

begin;

alter table public.seller_delivery_settings
  add column if not exists auto_prepare_orders boolean not null default false;

create or replace function public.auto_prepare_marketplace_order()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.status='confirmed'
    and (new.status is distinct from old.status or new.payment_status is distinct from old.payment_status)
    and (new.payment_method='cash_on_delivery' or new.payment_status='paid')
    and exists (
      select 1
      from public.seller_delivery_settings s
      where s.seller_id=new.seller_id
        and s.auto_prepare_orders=true
    )
  then
    update public.seller_orders
    set status='processing'
    where id=new.id and status='confirmed';

    update public.seller_orders
    set status='ready_for_delivery'
    where id=new.id and status='processing';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auto_prepare_marketplace_order on public.seller_orders;
create trigger trg_auto_prepare_marketplace_order
after update of status, payment_status on public.seller_orders
for each row
execute function public.auto_prepare_marketplace_order();

revoke all on function public.auto_prepare_marketplace_order() from public, anon, authenticated;

commit;
