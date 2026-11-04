-- Public storefront schema and access rules.
-- Run after src/authentication/authentication.sql in Supabase SQL Editor.
-- The seller catalogue module owns public.products; this script extends it.

do $$
begin
  if to_regclass('public.products') is null then
    raise exception 'public.products does not exist. Run the seller catalogue schema first, then rerun this script.';
  end if;
end $$;

alter table public.products
  add column if not exists is_active boolean not null default true,
  add column if not exists status text not null default 'published',
  add column if not exists is_featured boolean not null default false,
  add column if not exists is_recommended boolean not null default false,
  add column if not exists sales_count bigint not null default 0,
  add column if not exists views_count bigint not null default 0,
  add column if not exists discount_price numeric(12,2),
  add column if not exists stock integer;

alter table public.products
  drop constraint if exists products_status_check;
alter table public.products
  add constraint products_status_check
  check (status in ('draft','pending','published','inactive','rejected'));

create index if not exists products_storefront_created_idx
  on public.products (created_at desc)
  where is_active = true and status = 'published';
create index if not exists products_storefront_featured_idx
  on public.products (is_featured, created_at desc)
  where is_active = true and status = 'published';
create index if not exists products_storefront_recommended_idx
  on public.products (is_recommended, created_at desc)
  where is_active = true and status = 'published';

alter table public.products enable row level security;
drop policy if exists "Public can view published storefront products" on public.products;
create policy "Public can view published storefront products"
  on public.products for select to anon, authenticated
  using (is_active = true and status = 'published');

-- Match product_id to the existing seller catalogue products.id data type.
do $$
declare product_id_type text;
begin
  select format_type(a.atttypid, a.atttypmod)
    into product_id_type
  from pg_attribute a
  where a.attrelid = 'public.products'::regclass
    and a.attname = 'id'
    and a.attnum > 0
    and not a.attisdropped;

  if product_id_type is null then
    raise exception 'public.products must have an id column.';
  end if;

  execute format(
    'create table if not exists public.reviews (
      id uuid primary key default gen_random_uuid(),
      product_id %s not null references public.products(id) on delete cascade,
      customer_id uuid not null references auth.users(id) on delete cascade,
      customer_name text,
      rating smallint not null check (rating between 1 and 5),
      comment text,
      status text not null default ''pending'' check (status in (''pending'',''approved'',''rejected'')),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique (product_id, customer_id)
    )', product_id_type
  );
end $$;

create index if not exists reviews_product_approved_idx
  on public.reviews (product_id, created_at desc)
  where status = 'approved';

alter table public.reviews enable row level security;
drop policy if exists "Public can read approved product reviews" on public.reviews;
create policy "Public can read approved product reviews"
  on public.reviews for select to anon, authenticated
  using (status = 'approved');
drop policy if exists "Customers can submit their own product reviews" on public.reviews;
create policy "Customers can submit their own product reviews"
  on public.reviews for insert to authenticated
  with check (
    auth.uid() = customer_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'customer' and p.is_active = true
    )
    and exists (
      select 1 from public.products pr
      where pr.id = product_id and pr.is_active = true and pr.status = 'published'
    )
  );
drop policy if exists "Customers can update their pending reviews" on public.reviews;
create policy "Customers can update their pending reviews"
  on public.reviews for update to authenticated
  using (auth.uid() = customer_id and status = 'pending')
  with check (auth.uid() = customer_id and status = 'pending');

-- Only trusted administrators can moderate reviews.
drop policy if exists "Administrators can moderate reviews" on public.reviews;
create policy "Administrators can moderate reviews"
  on public.reviews for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active = true))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'administrator' and p.is_active = true));

-- Product category navigation is derived from published products.
-- Product images should use URLs from the seller catalogue's configured storage bucket.
