-- Administrator settings centre. Run after administrator.sql.
create table if not exists public.admin_platform_settings(
 section text primary key check(section in('account','identity','general','users','sellers','catalog','finance','orders','messaging','notifications','appearance','roles','security','legal','maintenance','audit')),
 config jsonb not null default '{}'::jsonb,
 updated_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.admin_platform_settings enable row level security;
drop policy if exists "Active administrators manage platform settings" on public.admin_platform_settings;
create policy "Active administrators manage platform settings" on public.admin_platform_settings for all to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());
grant select,insert,update on public.admin_platform_settings to authenticated;
create table if not exists public.admin_settings_audit(
 id uuid primary key default gen_random_uuid(),
 section text not null,
 changed_by uuid references public.profiles(id) on delete set null,
 old_config jsonb,
 new_config jsonb not null,
 changed_at timestamptz not null default now()
);
alter table public.admin_settings_audit enable row level security;
drop policy if exists "Active administrators read settings audit" on public.admin_settings_audit;
create policy "Active administrators read settings audit" on public.admin_settings_audit for select to authenticated using(public.is_active_marketplace_admin());
revoke insert,update,delete on public.admin_settings_audit from authenticated;
grant select on public.admin_settings_audit to authenticated;
create or replace function public.audit_admin_platform_settings() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.admin_settings_audit(section,changed_by,old_config,new_config)
 values(new.section,auth.uid(),case when tg_op='UPDATE' then old.config else null end,new.config);
 new.updated_by:=auth.uid();new.updated_at:=now();return new;
end; $$;
drop trigger if exists admin_platform_settings_audit on public.admin_platform_settings;
create trigger admin_platform_settings_audit before insert or update on public.admin_platform_settings for each row execute function public.audit_admin_platform_settings();
insert into public.admin_platform_settings(section,config) values
('account','{}'),('identity','{}'),('general','{"currency":"MWK","timezone":"Africa/Blantyre","site_visible":true,"registration_enabled":true}'),
('users','{"customer_registration":true,"seller_registration":true,"customer_auto_approval":true}'),
('sellers','{"seller_applications":true,"auto_approve_sellers":true,"seller_withdrawals_enabled":true}'),
('catalog','{"product_publishing":true,"auto_approve_products":false,"max_product_images":5,"max_image_size_mb":5}'),
('finance','{"currency":"MWK","minimum_withdrawal":0,"withdrawal_manual_approval":true}'),
('orders','{"delivery_enabled":true,"pickup_enabled":true,"guest_checkout":false}'),
('messaging','{"messaging_enabled":true,"customer_seller_messages":true,"suspended_messaging_block":true}'),
('notifications','{"in_app_notifications":true,"email_notifications":false,"sms_notifications":false,"push_notifications":false}'),
('appearance','{"theme":"system","featured_product_limit":8,"product_display_limit":24}'),
('roles','{"role_management_enabled":false}'),('security','{"enforce_2fa":false,"login_attempt_limit":5,"lockout_minutes":15}'),
('legal','{}'),('maintenance','{"maintenance_mode":false,"health_monitoring":true}'),('audit','{"audit_retention_days":365}')
on conflict(section) do nothing;