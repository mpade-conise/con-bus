-- Incremental wishlist and product-review enhancements. Run once in Supabase SQL Editor.
alter table public.reviews add column if not exists review_images jsonb not null default '[]'::jsonb;
alter table public.reviews add column if not exists seller_response text;
alter table public.reviews add column if not exists seller_response_at timestamptz;
create table if not exists public.review_reports (
 id uuid primary key default gen_random_uuid(),
 review_id uuid not null references public.reviews(id) on delete cascade,
 reporter_id uuid not null references public.profiles(id) on delete cascade,
 reason text not null check(length(trim(reason)) between 5 and 1000),
 status text not null default 'pending' check(status in('pending','reviewed','dismissed','action_taken')),
 created_at timestamptz not null default now(),
 unique(review_id,reporter_id)
);
create index if not exists review_reports_status_idx on public.review_reports(status,created_at desc);
create table if not exists public.customer_wishlist(
 customer_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(customer_id,product_id)
);
create index if not exists customer_wishlist_product_idx on public.customer_wishlist(product_id);
alter table public.customer_wishlist enable row level security;
drop policy if exists "Customers read own wishlist" on public.customer_wishlist;
create policy "Customers read own wishlist" on public.customer_wishlist for select to authenticated using(customer_id=auth.uid());
drop policy if exists "Customers add to own wishlist" on public.customer_wishlist;
create policy "Customers add to own wishlist" on public.customer_wishlist for insert to authenticated with check(customer_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='customer' and p.is_active));
drop policy if exists "Customers remove from own wishlist" on public.customer_wishlist;
create policy "Customers remove from own wishlist" on public.customer_wishlist for delete to authenticated using(customer_id=auth.uid());
grant select,insert,delete on public.customer_wishlist to authenticated;
grant select,insert,update,delete on public.reviews to authenticated;
alter table public.review_reports enable row level security;
drop policy if exists "Customers report product reviews" on public.review_reports;
create policy "Customers report product reviews" on public.review_reports for insert to authenticated with check(reporter_id=auth.uid() and exists(select 1 from public.reviews r where r.id=review_id and r.customer_id<>auth.uid()));
drop policy if exists "Users read own review reports" on public.review_reports;
create policy "Users read own review reports" on public.review_reports for select to authenticated using(reporter_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active));
drop policy if exists "Administrators manage review reports" on public.review_reports;
create policy "Administrators manage review reports" on public.review_reports for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active)) with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active));

-- Only customers who actually received an order containing the product may review it.
drop policy if exists "Customers can submit their own product reviews" on public.reviews;
create policy "Customers can submit their own product reviews" on public.reviews for insert to authenticated
with check(customer_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='customer' and p.is_active)
and exists(select 1 from public.seller_orders o where o.customer_id=auth.uid() and o.status='delivered'
and exists(select 1 from jsonb_array_elements(o.items) as item(value) where coalesce(item.value->>'product_id',item.value->>'id')=reviews.product_id::text)));
drop policy if exists "Customers can update their pending reviews" on public.reviews;
drop policy if exists "Customers manage own product reviews" on public.reviews;
create policy "Customers manage own product reviews" on public.reviews for update to authenticated
using(customer_id=auth.uid()) with check(customer_id=auth.uid());
drop policy if exists "Customers delete own product reviews" on public.reviews;
create policy "Customers delete own product reviews" on public.reviews for delete to authenticated using(customer_id=auth.uid());

drop policy if exists "Sellers read reviews for own products" on public.reviews;
create policy "Sellers read reviews for own products" on public.reviews for select to authenticated using(exists(select 1 from public.products p where p.id=product_id and p.seller_id=auth.uid()));

-- Sellers can respond only to reviews of their own products.
drop policy if exists "Sellers respond to reviews of own products" on public.reviews;
create policy "Sellers respond to reviews of own products" on public.reviews for update to authenticated
using(exists(select 1 from public.products p where p.id=product_id and p.seller_id=auth.uid()))
with check(exists(select 1 from public.products p where p.id=product_id and p.seller_id=auth.uid()));
grant select,insert,delete on public.review_reports to authenticated;
grant update(status) on public.review_reports to authenticated;
grant select,insert,update,delete on public.reviews to authenticated;

-- Review photos are public to view; only the uploader can add/remove files in their own folder.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-review-images','product-review-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Anyone can view product review images" on storage.objects;
create policy "Anyone can view product review images" on storage.objects for select using(bucket_id='product-review-images');
drop policy if exists "Customers upload own review images" on storage.objects;
create policy "Customers upload own review images" on storage.objects for insert to authenticated with check(bucket_id='product-review-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Customers delete own review images" on storage.objects;
create policy "Customers delete own review images" on storage.objects for delete to authenticated using(bucket_id='product-review-images' and (storage.foldername(name))[1]=auth.uid()::text);

-- Keep product aggregate ratings synchronized with approved reviews only.
create or replace function public.guard_product_review_update()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if auth.uid()=old.customer_id then
   if new.product_id is distinct from old.product_id or new.customer_id is distinct from old.customer_id or new.customer_name is distinct from old.customer_name or new.status is distinct from old.status or new.seller_response is distinct from old.seller_response or new.seller_response_at is distinct from old.seller_response_at or new.created_at is distinct from old.created_at then raise exception 'Customers may edit only their own rating, comment and review photos.'; end if;
 elsif exists(select 1 from public.products p where p.id=old.product_id and p.seller_id=auth.uid()) then
   if new.product_id is distinct from old.product_id or new.customer_id is distinct from old.customer_id or new.customer_name is distinct from old.customer_name or new.rating is distinct from old.rating or new.comment is distinct from old.comment or new.review_images is distinct from old.review_images or new.status is distinct from old.status or new.created_at is distinct from old.created_at then raise exception 'Sellers may only write or update their response.'; end if;
 elsif exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active) then
   return new;
 else
   raise exception 'Not allowed to edit this review.';
 end if;
 return new;
end;
$$;
drop trigger if exists guard_product_review_update_trigger on public.reviews;
create trigger guard_product_review_update_trigger before update on public.reviews for each row execute function public.guard_product_review_update();

create or replace function public.refresh_product_review_rating()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_product_id uuid;
begin
 v_product_id:=coalesce(new.product_id,old.product_id);
 update public.products p set rating=coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.product_id=v_product_id and r.status='approved'),0),
 rating_count=(select count(*)::integer from public.reviews r where r.product_id=v_product_id and r.status='approved')
 where p.id=v_product_id;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$$;
drop trigger if exists refresh_product_review_rating_trigger on public.reviews;
create trigger refresh_product_review_rating_trigger after insert or update of rating,status or delete on public.reviews for each row execute function public.refresh_product_review_rating();

-- Existing reviews are also reflected in the aggregate fields.
update public.products p set rating=coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.product_id=p.id and r.status='approved'),0),
rating_count=(select count(*)::integer from public.reviews r where r.product_id=p.id and r.status='approved');
