-- Apply in Supabase SQL Editor.
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text,business_name text,phone text,bio text,avatar_url text,
 role text not null default 'customer' check(role in('customer','seller','administrator')),
 is_active boolean not null default true,deactivated_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
declare requested_role text;
begin
 requested_role:=coalesce(new.raw_user_meta_data->>'role','customer');
 if requested_role not in('customer','seller') then requested_role:='customer'; end if;
 insert into public.profiles(id,full_name,business_name,phone,role)
 values(new.id,new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'business_name',new.raw_user_meta_data->>'phone',requested_role)
 on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
alter table public.profiles enable row level security;
drop policy if exists "Read own profile" on public.profiles;
create policy "Read own profile" on public.profiles for select to authenticated using(auth.uid()=id);
drop policy if exists "Insert own profile" on public.profiles;
create policy "Insert own profile" on public.profiles for insert to authenticated with check(auth.uid()=id and role in('customer','seller'));
drop policy if exists "Update own profile" on public.profiles;
create policy "Update own profile" on public.profiles for update to authenticated using(auth.uid()=id) with check(auth.uid()=id);
create or replace function public.prevent_profile_role_change() returns trigger language plpgsql as $$
begin
 if new.role is distinct from old.role and coalesce(auth.role(),'') <> 'service_role' then raise exception 'Role changes require trusted administrator privileges.'; end if;
 return new;
end; $$;
drop trigger if exists protect_profile_role on public.profiles;
create trigger protect_profile_role before update on public.profiles for each row execute procedure public.prevent_profile_role_change();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-images','profile-images',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
drop policy if exists "Upload own avatar" on storage.objects;
create policy "Upload own avatar" on storage.objects for insert to authenticated with check(bucket_id='profile-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Update own avatar" on storage.objects;
create policy "Update own avatar" on storage.objects for update to authenticated using(bucket_id='profile-images' and (storage.foldername(name))[1]=auth.uid()::text);
