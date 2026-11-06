-- Inventory availability automation for Market Hub.
-- Run once in Supabase SQL Editor after homepage.sql and orders.sql.
-- Stock is reserved atomically by place_marketplace_order at checkout.
-- Cancellation restores the reserved quantity; this trigger keeps availability in sync.
create or replace function public.sync_product_stock_availability()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.stock <= 0 then
    new.availability_status := 'out_of_stock';
  elsif old.stock <= 0
    and old.availability_status = 'out_of_stock'
    and new.availability_status = old.availability_status then
    new.availability_status := 'available';
  end if;
  return new;
end;
$$;

drop trigger if exists products_sync_stock_availability on public.products;
create trigger products_sync_stock_availability
before update of stock on public.products
for each row execute function public.sync_product_stock_availability();

update public.products
set availability_status = 'out_of_stock'
where coalesce(stock, 0) <= 0
  and availability_status is distinct from 'out_of_stock';

update public.products
set availability_status = 'available'
where stock > 0
  and availability_status = 'out_of_stock';
