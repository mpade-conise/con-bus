create or replace function public.is_marketplace_customer(p_user_id uuid)
returns boolean language sql stable security definer set search_path=public
as $function$
 select exists(select 1 from public.profiles where id=p_user_id and role='customer' and is_active);
$function$;
create or replace function public.is_marketplace_seller(p_user_id uuid)
returns boolean language sql stable security definer set search_path=public
as $function$
 select exists(select 1 from public.profiles where id=p_user_id and role='seller' and is_active);
$function$;

drop policy if exists "Delegated administrators manage customers" on public.profiles;
create policy "Delegated administrators manage customers" on public.profiles for update to authenticated
using (public.has_admin_permission('customers.manage') and public.is_marketplace_customer(id))
with check (public.has_admin_permission('customers.manage') and public.is_marketplace_customer(id));
drop policy if exists "Delegated administrators read customers" on public.profiles;
create policy "Delegated administrators read customers" on public.profiles for select to authenticated
using (public.has_admin_permission('customers.view') and public.is_marketplace_customer(id));
create policy "Delegated administrators read sellers" on public.profiles for select to authenticated
using (public.has_admin_permission('sellers.view') and public.is_marketplace_seller(id));
create policy "Delegated administrators read seller stores" on public.seller_stores for select to authenticated
using (public.has_admin_permission('sellers.view'));
create policy "Delegated administrators read marketplace orders" on public.seller_orders for select to authenticated
using (public.has_admin_permission('orders.view'));
create policy "Delegated administrators read all products" on public.products for select to authenticated
using (public.has_admin_permission('catalog.view'));
create policy "Delegated administrators read user reports" on public.user_reports for select to authenticated
using (public.has_admin_permission('reports.view'));
create policy "Delegated administrators read product reports" on public.product_reports for select to authenticated
using (public.has_admin_permission('reports.view'));
create policy "Delegated administrators read review reports" on public.review_reports for select to authenticated
using (public.has_admin_permission('reviews.view'));
create policy "Delegated administrators read message reports" on public.message_reports for select to authenticated
using (public.has_admin_permission('messaging.moderate'));

create or replace function public.log_admin_table_change()
returns trigger language plpgsql security definer set search_path=public
as $function$
declare old_row jsonb; new_row jsonb; record_key text;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active) then
  return case when tg_op='DELETE' then old else new end;
 end if;
 old_row:=case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
 new_row:=case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
 record_key:=coalesce(new_row->>'id',old_row->>'id');
 insert into public.admin_audit_logs(actor_id,action,table_name,record_id,old_data,new_data)
 values(auth.uid(),lower(tg_op),tg_table_name,record_key,old_row,new_row);
 return case when tg_op='DELETE' then old else new end;
end;
$function$;
