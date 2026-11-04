-- Homepage / Public Storefront database.
-- Run after src/authentication/authentication.sql in Supabase SQL Editor.
-- This script creates the homepage tables from scratch when only profiles exists.
create extension if not exists pgcrypto;

create or replace function public.set_homepage_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  image_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.seller_stores (
  seller_id uuid primary key references public.profiles(id) on delete cascade,
  store_name text not null,
  description text,
  logo_url text,
  banner_url text,
  city text,
  region text,
  country text not null default 'Malawi',
  contact_email text,
  website_url text,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  category_id uuid references public.product_categories(id) on delete set null,
  name text not null,
  title text,
  description text,
  brand text,
  category text,
  category_name text,
  price numeric(12,2) not null check (price >= 0),
  discount_price numeric(12,2) check (discount_price is null or discount_price >= 0),
  sale_price numeric(12,2) check (sale_price is null or sale_price >= 0),
  image_url text,
  images jsonb not null default '[]'::jsonb,
  stock integer not null default 0 check (stock >= 0),
  is_active boolean not null default true,
  status text not null default 'draft' check (status in ('draft','pending','published','inactive','rejected')),
  is_featured boolean not null default false,
  is_recommended boolean not null default false,
  sales_count bigint not null default 0 check (sales_count >= 0),
  views_count bigint not null default 0 check (views_count >= 0),
  rating numeric(2,1) not null default 0 check (rating between 0 and 5),
  rating_count integer not null default 0 check (rating_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  customer_name text,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, customer_id)
);

create table if not exists public.promotional_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text,
  image_url text,
  cta_label text not null default 'Explore offers',
  cta_url text not null default '/?sort=discount#products',
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index if not exists products_public_latest_idx on public.products(created_at desc) where is_active and status = 'published';
create index if not exists products_public_featured_idx on public.products(is_featured, created_at desc) where is_active and status = 'published';
create index if not exists products_public_recommended_idx on public.products(is_recommended, created_at desc) where is_active and status = 'published';
create index if not exists products_public_category_idx on public.products(category_id) where is_active and status = 'published';
create index if not exists products_public_price_idx on public.products(price) where is_active and status = 'published';
create index if not exists reviews_approved_product_idx on public.reviews(product_id, created_at desc) where status = 'approved';
create index if not exists banners_public_order_idx on public.promotional_banners(sort_order, created_at desc) where is_active;

drop trigger if exists product_categories_updated_at on public.product_categories;
create trigger product_categories_updated_at before update on public.product_categories for each row execute function public.set_homepage_updated_at();
drop trigger if exists seller_stores_updated_at on public.seller_stores;
create trigger seller_stores_updated_at before update on public.seller_stores for each row execute function public.set_homepage_updated_at();
drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products for each row execute function public.set_homepage_updated_at();
drop trigger if exists reviews_updated_at on public.reviews;
create trigger reviews_updated_at before update on public.reviews for each row execute function public.set_homepage_updated_at();
drop trigger if exists promotional_banners_updated_at on public.promotional_banners;
create trigger promotional_banners_updated_at before update on public.promotional_banners for each row execute function public.set_homepage_updated_at();

alter table public.product_categories enable row level security;
alter table public.seller_stores enable row level security;
alter table public.products enable row level security;
alter table public.reviews enable row level security;
alter table public.promotional_banners enable row level security;

-- Categories: public visitors can browse active categories; administrators manage them.
drop policy if exists "Public can read active categories" on public.product_categories;
create policy "Public can read active categories" on public.product_categories for select to anon, authenticated using (is_active = true);
drop policy if exists "Administrators manage categories" on public.product_categories;
create policy "Administrators manage categories" on public.product_categories for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active));

-- Store profiles deliberately contain private phone numbers; only this public-safe store table is exposed.
drop policy if exists "Public can read public seller stores" on public.seller_stores;
create policy "Public can read public seller stores" on public.seller_stores for select to anon, authenticated using (is_public = true);
drop policy if exists "Sellers can read own store" on public.seller_stores;
create policy "Sellers can read own store" on public.seller_stores for select to authenticated using (seller_id = auth.uid());
drop policy if exists "Sellers can create own store" on public.seller_stores;
create policy "Sellers can create own store" on public.seller_stores for insert to authenticated
with check (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active));
drop policy if exists "Sellers can update own store" on public.seller_stores;
create policy "Sellers can update own store" on public.seller_stores for update to authenticated
using (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active))
with check (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active));

-- Products: everyone sees only published active listings; sellers manage only their own products.
drop policy if exists "Public can view published storefront products" on public.products;
create policy "Public can view published storefront products" on public.products for select to anon, authenticated using (is_active = true and status = 'published');
drop policy if exists "Sellers can view own products" on public.products;
create policy "Sellers can view own products" on public.products for select to authenticated using (seller_id = auth.uid());
drop policy if exists "Sellers can create own products" on public.products;
create policy "Sellers can create own products" on public.products for insert to authenticated
with check (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active));
drop policy if exists "Sellers can update own products" on public.products;
create policy "Sellers can update own products" on public.products for update to authenticated
using (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active))
with check (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active));
drop policy if exists "Sellers can delete own products" on public.products;
create policy "Sellers can delete own products" on public.products for delete to authenticated
using (seller_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'seller' and p.is_active));
drop policy if exists "Administrators manage products" on public.products;
create policy "Administrators manage products" on public.products for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active));

-- Reviews: only approved reviews are public; customers submit and edit their own pending reviews.
drop policy if exists "Public can read approved product reviews" on public.reviews;
create policy "Public can read approved product reviews" on public.reviews for select to anon, authenticated using (status = 'approved');
drop policy if exists "Customers can read own reviews" on public.reviews;
create policy "Customers can read own reviews" on public.reviews for select to authenticated using (customer_id = auth.uid());
drop policy if exists "Customers can submit their own product reviews" on public.reviews;
create policy "Customers can submit their own product reviews" on public.reviews for insert to authenticated
with check (
  customer_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'customer' and p.is_active)
  and exists (select 1 from public.products pr where pr.id = product_id and pr.is_active and pr.status = 'published')
);
drop policy if exists "Customers can update their pending reviews" on public.reviews;
create policy "Customers can update their pending reviews" on public.reviews for update to authenticated
using (customer_id = auth.uid() and status = 'pending')
with check (customer_id = auth.uid() and status = 'pending');
drop policy if exists "Administrators moderate reviews" on public.reviews;
create policy "Administrators moderate reviews" on public.reviews for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active));

-- Promotional banners are public only while active and within their schedule; administrators manage campaigns.
drop policy if exists "Public can read current promotional banners" on public.promotional_banners;
create policy "Public can read current promotional banners" on public.promotional_banners for select to anon, authenticated
using (is_active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
drop policy if exists "Administrators manage promotional banners" on public.promotional_banners;
create policy "Administrators manage promotional banners" on public.promotional_banners for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active));

-- Product categories are also stored on each product as category/category_name for storefront compatibility.
-- New sellers must create a seller_stores row and product rows from the seller dashboard.
