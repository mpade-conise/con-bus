alter table public.profiles add column if not exists admin_access_level text not null default 'restricted';
alter table public.profiles drop constraint if exists profiles_admin_access_level_check;
alter table public.profiles add constraint profiles_admin_access_level_check check (admin_access_level in ('full','restricted'));
update public.profiles set admin_access_level='full' where role='administrator' and is_active=true;
update public.profiles set admin_access_level='restricted' where role<>'administrator';

create table if not exists public.admin_permission_grants (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 permission text not null,
 granted_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(user_id,permission)
);
create index if not exists admin_permission_grants_user_idx on public.admin_permission_grants(user_id);
alter table public.admin_permission_grants enable row level security;
drop policy if exists "Administrators read admin permission grants" on public.admin_permission_grants;
create policy "Administrators read admin permission grants" on public.admin_permission_grants for select to authenticated using (user_id=auth.uid() or public.is_active_marketplace_admin());

create or replace function public.is_active_marketplace_admin()
returns boolean language sql stable security definer set search_path=public
as $function$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active and p.admin_access_level='full');
$function$;

create or replace function public.has_admin_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public
as $function$
 select exists(
  select 1 from public.profiles p
  where p.id=auth.uid() and p.role='administrator' and p.is_active
  and (p.admin_access_level='full' or exists(select 1 from public.admin_permission_grants g where g.user_id=p.id and g.permission=p_permission))
 );
$function$;

create or replace function public.get_my_admin_permissions()
returns text[] language sql stable security definer set search_path=public
as $function$
 select case
  when public.is_active_marketplace_admin() then array[
   'dashboard.view','customers.view','customers.manage','sellers.view','sellers.manage',
   'catalog.view','catalog.manage','orders.view','orders.manage','reports.view',
   'ads.manage','homepage.manage','promotions.manage','analytics.view','engagement.view',
   'reviews.view','reviews.manage','messaging.moderate','finance.read','settings.manage',
   'security.view','audit.view','alerts.manage','admin.team.manage'
  ]::text[]
  else coalesce((select array_agg(g.permission order by g.permission) from public.admin_permission_grants g join public.profiles p on p.id=g.user_id where p.id=auth.uid() and p.role='administrator' and p.is_active and p.admin_access_level='restricted'),array[]::text[])
 end;
$function$;

create or replace function public.admin_set_permissions(p_user_id uuid,p_permissions text[])
returns void language plpgsql security definer set search_path=public
as $function$
declare allowed text[]:=array[
 'dashboard.view','customers.view','customers.manage','sellers.view','sellers.manage',
 'catalog.view','catalog.manage','orders.view','orders.manage','reports.view',
 'ads.manage','homepage.manage','promotions.manage','analytics.view','engagement.view',
 'reviews.view','reviews.manage','messaging.moderate','finance.read','security.view','audit.view','alerts.manage'
];
begin
 if not public.is_active_marketplace_admin() then raise exception 'Only a full administrator can manage permissions'; end if;
 if p_user_id=auth.uid() then raise exception 'You cannot change your own administrator permissions'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id and role='administrator' and is_active) then raise exception 'Target must be an active administrator account'; end if;
 if exists(select 1 from unnest(coalesce(p_permissions,array[]::text[])) x where not (x=any(allowed))) then raise exception 'One or more permissions are not recognized'; end if;
 delete from public.admin_permission_grants where user_id=p_user_id;
 insert into public.admin_permission_grants(user_id,permission,granted_by)
 select p_user_id,x,auth.uid() from (select distinct unnest(coalesce(p_permissions,array[]::text[])) x) q;
 update public.profiles set admin_access_level='restricted',updated_at=now() where id=p_user_id;
 insert into public.admin_audit_logs(actor_id,action,table_name,record_id,new_data)
 values(auth.uid(),'permissions.updated','profiles',p_user_id::text,jsonb_build_object('permissions',coalesce(p_permissions,array[]::text[]),'access_level','restricted'));
end;
$function$;

create or replace function public.admin_set_access_level(p_user_id uuid,p_access_level text)
returns void language plpgsql security definer set search_path=public
as $function$
begin
 if not public.is_active_marketplace_admin() then raise exception 'Only a full administrator can manage administrator access'; end if;
 if p_user_id=auth.uid() then raise exception 'You cannot change your own access level'; end if;
 if p_access_level not in ('full','restricted') then raise exception 'Invalid administrator access level'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id and role='administrator' and is_active) then raise exception 'Target must be an active administrator account'; end if;
 update public.profiles set admin_access_level=p_access_level,updated_at=now() where id=p_user_id;
 if p_access_level='full' then delete from public.admin_permission_grants where user_id=p_user_id; end if;
 insert into public.admin_audit_logs(actor_id,action,table_name,record_id,new_data)
 values(auth.uid(),'access_level.updated','profiles',p_user_id::text,jsonb_build_object('access_level',p_access_level));
end;
$function$;

create table if not exists public.admin_audit_logs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references public.profiles(id) on delete set null,
 action text not null,
 table_name text not null,
 record_id text,
 old_data jsonb,
 new_data jsonb,
 created_at timestamptz not null default now()
);
create index if not exists admin_audit_logs_created_idx on public.admin_audit_logs(created_at desc);
create index if not exists admin_audit_logs_actor_idx on public.admin_audit_logs(actor_id,created_at desc);
alter table public.admin_audit_logs enable row level security;
drop policy if exists "Administrators read enterprise audit logs" on public.admin_audit_logs;
create policy "Administrators read enterprise audit logs" on public.admin_audit_logs for select to authenticated using (public.has_admin_permission('audit.view'));

create table if not exists public.admin_alerts (
 id uuid primary key default gen_random_uuid(),
 alert_type text not null,
 severity text not null default 'info' check (severity in ('info','warning','critical')),
 title text not null,
 details text,
 source_table text,
 source_record_id text,
 is_read boolean not null default false,
 created_at timestamptz not null default now(),
 read_at timestamptz
);
create index if not exists admin_alerts_created_idx on public.admin_alerts(created_at desc);
alter table public.admin_alerts enable row level security;
drop policy if exists "Administrators read enterprise alerts" on public.admin_alerts;
create policy "Administrators read enterprise alerts" on public.admin_alerts for select to authenticated using (public.has_admin_permission('security.view') or public.has_admin_permission('alerts.manage'));
drop policy if exists "Administrators acknowledge enterprise alerts" on public.admin_alerts;
create policy "Administrators acknowledge enterprise alerts" on public.admin_alerts for update to authenticated using (public.has_admin_permission('alerts.manage')) with check (public.has_admin_permission('alerts.manage'));

create or replace function public.guard_profile_admin_fields()
returns trigger language plpgsql security definer set search_path=public
as $function$
begin
 if auth.uid() is not null and auth.uid()=old.id and not public.is_active_marketplace_admin()
 and (new.role is distinct from old.role or new.is_active is distinct from old.is_active or new.admin_access_level is distinct from old.admin_access_level) then
  raise exception 'Only a full administrator can change administrator role, status or access level';
 end if;
 if new.role<>'administrator' then new.admin_access_level:='restricted'; end if;
 return new;
end;
$function$;
drop trigger if exists protect_profile_admin_fields on public.profiles;
create trigger protect_profile_admin_fields before update on public.profiles for each row execute function public.guard_profile_admin_fields();

create or replace function public.log_admin_table_change()
returns trigger language plpgsql security definer set search_path=public
as $function$
declare old_row jsonb; new_row jsonb; record_key text;
begin
 if auth.uid() is null then return coalesce(new,old); end if;
 old_row:=case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
 new_row:=case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
 record_key:=coalesce(new_row->>'id',old_row->>'id');
 insert into public.admin_audit_logs(actor_id,action,table_name,record_id,old_data,new_data)
 values(auth.uid(),lower(tg_op),tg_table_name,record_key,old_row,new_row);
 return coalesce(new,old);
end;
$function$;

drop trigger if exists admin_audit_products on public.products;
create trigger admin_audit_products after insert or update or delete on public.products for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_stores on public.seller_stores;
create trigger admin_audit_stores after insert or update or delete on public.seller_stores for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_orders on public.seller_orders;
create trigger admin_audit_orders after insert or update or delete on public.seller_orders for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_ads on public.marketplace_ads;
create trigger admin_audit_ads after insert or update or delete on public.marketplace_ads for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_banners on public.promotional_banners;
create trigger admin_audit_banners after insert or update or delete on public.promotional_banners for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_categories on public.product_categories;
create trigger admin_audit_categories after insert or update or delete on public.product_categories for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_reviews on public.reviews;
create trigger admin_audit_reviews after insert or update or delete on public.reviews for each row execute function public.log_admin_table_change();
drop trigger if exists admin_audit_settings on public.admin_platform_settings;
create trigger admin_audit_settings after insert or update or delete on public.admin_platform_settings for each row execute function public.log_admin_table_change();

create or replace function public.create_admin_security_alert()
returns trigger language plpgsql security definer set search_path=public
as $function$
begin
 if new.event_type ilike '%fail%' or new.event_type ilike '%suspicious%' or new.event_type ilike '%locked%' or new.event_type ilike '%password%' then
  insert into public.admin_alerts(alert_type,severity,title,details,source_table,source_record_id)
  values('account_security','warning','Account security event',format('Event: %s · User ID: %s',new.event_type,new.user_id),'account_security_events',new.id::text);
 end if;
 return new;
end;
$function$;
drop trigger if exists admin_security_alerts on public.account_security_events;
create trigger admin_security_alerts after insert on public.account_security_events for each row execute function public.create_admin_security_alert();

drop policy if exists "Administrators read security events" on public.account_security_events;
create policy "Administrators read security events" on public.account_security_events for select to authenticated using (public.has_admin_permission('security.view'));

drop policy if exists "Administrators manage products" on public.products;
create policy "Administrators manage products" on public.products for all to authenticated using (public.has_admin_permission('catalog.manage')) with check (public.has_admin_permission('catalog.manage'));
drop policy if exists "Administrators manage categories" on public.product_categories;
create policy "Administrators manage categories" on public.product_categories for all to authenticated using (public.has_admin_permission('catalog.manage')) with check (public.has_admin_permission('catalog.manage'));
drop policy if exists "Administrators manage promotional banners" on public.promotional_banners;
create policy "Administrators manage promotional banners" on public.promotional_banners for all to authenticated using (public.has_admin_permission('homepage.manage')) with check (public.has_admin_permission('homepage.manage'));
drop policy if exists "Administrators moderate reviews" on public.reviews;
create policy "Administrators moderate reviews" on public.reviews for all to authenticated using (public.has_admin_permission('reviews.manage')) with check (public.has_admin_permission('reviews.manage'));
drop policy if exists "Administrators update review reports" on public.review_reports;
create policy "Administrators update review reports" on public.review_reports for update to authenticated using (public.has_admin_permission('reviews.manage')) with check (public.has_admin_permission('reviews.manage'));
drop policy if exists "Users read own review reports" on public.review_reports;
create policy "Users read own review reports" on public.review_reports for select to authenticated using (reporter_id=auth.uid() or public.has_admin_permission('reviews.view'));
drop policy if exists "Administrators update message reports" on public.message_reports;
create policy "Administrators update message reports" on public.message_reports for update to authenticated using (public.has_admin_permission('messaging.moderate')) with check (public.has_admin_permission('messaging.moderate'));
drop policy if exists "Administrators read marketplace refund evidence" on public.marketplace_refund_evidence;
create policy "Administrators read marketplace refund evidence" on public.marketplace_refund_evidence for select to authenticated using (public.has_admin_permission('finance.read'));
drop policy if exists "Administrators read seller refund recoveries" on public.seller_refund_recoveries;
create policy "Administrators read seller refund recoveries" on public.seller_refund_recoveries for select to authenticated using (public.has_admin_permission('finance.read'));
drop policy if exists "Administrators read withdrawals" on public.seller_withdrawals;
create policy "Administrators read withdrawals" on public.seller_withdrawals for select to authenticated using (public.has_admin_permission('finance.read'));

create policy "Delegated administrators manage marketplace ads" on public.marketplace_ads for all to authenticated using (public.has_admin_permission('ads.manage')) with check (public.has_admin_permission('ads.manage'));
create policy "Delegated administrators manage customers" on public.profiles for update to authenticated using (public.has_admin_permission('customers.manage')) with check (public.has_admin_permission('customers.manage'));
create policy "Delegated administrators read customers" on public.profiles for select to authenticated using (public.has_admin_permission('customers.view'));
