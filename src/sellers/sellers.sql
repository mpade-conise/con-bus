-- Seller workspace schema. Run after authentication.sql and homepage.sql.
-- All seller-owned records are isolated by auth.uid() and RLS.
create table if not exists public.seller_categories (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete cascade,
 name text not null,
 slug text not null,
 created_at timestamptz not null default now(),
 unique(seller_id,slug),
 unique(seller_id,name)
);
create table if not exists public.seller_orders (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete restrict,
 customer_id uuid references public.profiles(id) on delete set null,
 customer_name text,
 order_number text,
 items jsonb not null default '[]'::jsonb,
 subtotal numeric(12,2) not null default 0 check(subtotal>=0),
 shipping_amount numeric(12,2) not null default 0 check(shipping_amount>=0),
 total_amount numeric(12,2) not null default 0 check(total_amount>=0),
 currency text not null default 'MWK',
 status text not null default 'pending' check(status in('pending','confirmed','processing','shipped','delivered','cancelled')),
 payment_status text not null default 'pending' check(payment_status in('pending','paid','failed','refunded')),
 seller_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.seller_messages (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete cascade,
 customer_id uuid references public.profiles(id) on delete set null,
 customer_name text,
 customer_email text,
 subject text,
 message text not null,
 is_read boolean not null default false,
 created_at timestamptz not null default now()
);
create table if not exists public.seller_transactions (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete restrict,
 order_id uuid references public.seller_orders(id) on delete set null,
 reference text,
 transaction_type text not null default 'payment' check(transaction_type in('payment','payout','refund','fee','adjustment')),
 amount numeric(12,2) not null check(amount>=0),
 currency text not null default 'MWK',
 status text not null default 'pending' check(status in('pending','processing','completed','failed','reversed')),
 provider text,
 created_at timestamptz not null default now()
);
create index if not exists seller_categories_owner_idx on public.seller_categories(seller_id);
create index if not exists seller_orders_owner_date_idx on public.seller_orders(seller_id,created_at desc);
create index if not exists seller_orders_customer_idx on public.seller_orders(customer_id);
create index if not exists seller_messages_owner_date_idx on public.seller_messages(seller_id,created_at desc);
create index if not exists seller_transactions_owner_date_idx on public.seller_transactions(seller_id,created_at desc);

create or replace function public.seller_touch_updated_at() returns trigger language plpgsql set search_path=public as $$
begin new.updated_at=now(); return new; end; $$;
drop trigger if exists seller_orders_touch_updated_at on public.seller_orders;
create trigger seller_orders_touch_updated_at before update on public.seller_orders for each row execute function public.seller_touch_updated_at();

alter table public.seller_categories enable row level security;
alter table public.seller_orders enable row level security;
alter table public.seller_messages enable row level security;
alter table public.seller_transactions enable row level security;

drop policy if exists "Sellers manage own categories" on public.seller_categories;
create policy "Sellers manage own categories" on public.seller_categories for all to authenticated
using(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active))
with check(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));

drop policy if exists "Sellers read own orders" on public.seller_orders;
create policy "Sellers read own orders" on public.seller_orders for select to authenticated
using(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));
drop policy if exists "Sellers update own order status" on public.seller_orders;
create policy "Sellers update own order status" on public.seller_orders for update to authenticated
using(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active))
with check(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));

drop policy if exists "Sellers read own messages" on public.seller_messages;
create policy "Sellers read own messages" on public.seller_messages for select to authenticated
using(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));
drop policy if exists "Sellers mark own messages read" on public.seller_messages;
create policy "Sellers mark own messages read" on public.seller_messages for update to authenticated
using(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active))
with check(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));

drop policy if exists "Sellers read own transactions" on public.seller_transactions;
create policy "Sellers read own transactions" on public.seller_transactions for select to authenticated
using(seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));

grant select,insert,update,delete on public.seller_categories to authenticated;
grant select on public.seller_orders to authenticated;
grant update(status,seller_note) on public.seller_orders to authenticated;
grant select,update(is_read) on public.seller_messages to authenticated;
grant select on public.seller_transactions to authenticated;

-- Extended product catalogue fields. Safe to run on an existing products table.
alter table public.products add column if not exists sku text;
alter table public.products add column if not exists condition text not null default 'new' check(condition in('new','used','refurbished'));
alter table public.products add column if not exists availability_status text not null default 'available' check(availability_status in('available','out_of_stock','preorder'));
alter table public.products add column if not exists visibility text not null default 'public' check(visibility in('public','private'));
alter table public.products add column if not exists tags text[] not null default '{}';
alter table public.products add column if not exists specifications jsonb not null default '[]'::jsonb;
alter table public.products add column if not exists variations jsonb not null default '[]'::jsonb;
create unique index if not exists products_seller_sku_unique on public.products(seller_id,sku) where sku is not null and sku <> '';
create index if not exists products_public_catalogue_idx on public.products(created_at desc) where is_active and status='published' and visibility='public';

-- Sellers may edit listing content and stock, but cannot forge sales, views, ratings or recommendation metrics.
revoke insert,update on public.products from authenticated;
grant insert(seller_id,name,title,description,brand,category,category_name,price,discount_price,sale_price,image_url,images,stock,is_active,status,sku,condition,availability_status,visibility,is_featured,tags,specifications,variations) on public.products to authenticated;
grant update(name,title,description,brand,category,category_name,price,discount_price,sale_price,image_url,images,stock,is_active,status,sku,condition,availability_status,visibility,is_featured,tags,specifications,variations) on public.products to authenticated;

-- Store/product uploads are publicly viewable but only the owning authenticated seller can upload/manage their own path.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('seller-assets','seller-assets',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Sellers upload own assets" on storage.objects;
create policy "Sellers upload own assets" on storage.objects for insert to authenticated
with check(bucket_id='seller-assets' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));
drop policy if exists "Sellers update own assets" on storage.objects;
create policy "Sellers update own assets" on storage.objects for update to authenticated
using(bucket_id='seller-assets' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active))
with check(bucket_id='seller-assets' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));
drop policy if exists "Sellers delete own assets" on storage.objects;
create policy "Sellers delete own assets" on storage.objects for delete to authenticated
using(bucket_id='seller-assets' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller' and p.is_active));
