-- Administrator dashboard extensions. Run after the core marketplace, messaging and payment migrations.
alter table public.seller_stores add column if not exists verification_status text not null default 'unverified' check(verification_status in('unverified','pending','verified','rejected'));
alter table public.seller_stores add column if not exists verified_at timestamptz;
alter table public.profiles add column if not exists deactivated_at timestamptz;

-- Security-definer predicate avoids recursive profiles RLS when administrators list accounts.
create or replace function public.is_active_marketplace_admin()
returns boolean language sql stable security definer set search_path=public as $
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active);\n$;revoke all on function public.is_active_marketplace_admin() from public,anon;
grant execute on function public.is_active_marketplace_admin() to authenticated;

create table if not exists public.product_reports(
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 reason text not null,
 details text,
 status text not null default 'pending' check(status in('pending','reviewed','dismissed','actioned')),
 created_at timestamptz not null default now(),
 unique(reporter_id,product_id)
);
create table if not exists public.user_reports(
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete cascade,
 reported_user_id uuid not null references public.profiles(id) on delete cascade,
 reason text not null,
 details text,
 status text not null default 'pending' check(status in('pending','reviewed','dismissed','actioned')),
 created_at timestamptz not null default now(),
 check(reporter_id<>reported_user_id),
 unique(reporter_id,reported_user_id)
);
create table if not exists public.marketplace_ads(
 id uuid primary key default gen_random_uuid(),
 title text not null,
 description text,
 image_url text,
 target_url text,
 is_active boolean not null default true,
 starts_at timestamptz,
 ends_at timestamptz,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.product_reports enable row level security;
alter table public.user_reports enable row level security;
alter table public.marketplace_ads enable row level security;
alter table public.message_reports enable row level security;

drop policy if exists "Users submit product reports" on public.product_reports;
create policy "Users submit product reports" on public.product_reports for insert to authenticated with check(reporter_id=auth.uid());
drop policy if exists "Administrators manage product reports" on public.product_reports;
create policy "Administrators manage product reports" on public.product_reports for all to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());
drop policy if exists "Users submit user reports" on public.user_reports;
create policy "Users submit user reports" on public.user_reports for insert to authenticated with check(reporter_id=auth.uid() and reported_user_id<>auth.uid());
drop policy if exists "Administrators manage user reports" on public.user_reports;
create policy "Administrators manage user reports" on public.user_reports for all to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());

drop policy if exists "Administrators manage marketplace ads" on public.marketplace_ads;
create policy "Administrators manage marketplace ads" on public.marketplace_ads for all to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());
drop policy if exists "Users read active marketplace ads" on public.marketplace_ads;
create policy "Users read active marketplace ads" on public.marketplace_ads for select to authenticated using(is_active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()));

drop policy if exists "Administrators manage profiles" on public.profiles;
create policy "Administrators manage profiles" on public.profiles for update to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());
drop policy if exists "Administrators manage seller stores" on public.seller_stores;
create policy "Administrators manage seller stores" on public.seller_stores for all to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());
drop policy if exists "Administrators review message reports" on public.message_reports;
create policy "Administrators review message reports" on public.message_reports for all to authenticated using(public.is_active_marketplace_admin()) with check(public.is_active_marketplace_admin());

grant select,insert,update,delete on public.product_reports,public.user_reports,public.marketplace_ads to authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update,delete on public.seller_stores to authenticated;
grant select,update on public.message_reports to authenticated;

drop policy if exists "Administrators read all profiles" on public.profiles;
create policy "Administrators read all profiles" on public.profiles for select to authenticated using(public.is_active_marketplace_admin());
drop policy if exists "Administrators read marketplace orders" on public.seller_orders;
create policy "Administrators read marketplace orders" on public.seller_orders for select to authenticated using(public.is_active_marketplace_admin());
drop policy if exists "Administrators read marketplace transactions" on public.marketplace_transactions;
create policy "Administrators read marketplace transactions" on public.marketplace_transactions for select to authenticated using(public.is_active_marketplace_admin());
