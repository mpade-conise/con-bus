-- Security & privacy hardening migration.
-- Run after authentication.sql, messaging/message.sql and administrator/administrator.sql.
create extension if not exists pgcrypto;
create or replace function public.guard_profile_security_fields()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if (new.role is distinct from old.role or new.is_active is distinct from old.is_active or new.deactivated_at is distinct from old.deactivated_at)
   and coalesce(auth.role(),'')<>'service_role'
   and not coalesce(public.is_active_marketplace_admin(),false) then
   raise exception 'Account role and access status can only be changed by trusted administrators.';
 end if;
 if new.id is distinct from old.id or new.created_at is distinct from old.created_at then raise exception 'Profile identity fields cannot be changed.'; end if;
 return new;
end;
$$;
drop trigger if exists protect_profile_role on public.profiles;
drop trigger if exists protect_profile_security_fields on public.profiles;
create trigger protect_profile_security_fields before update on public.profiles for each row execute function public.guard_profile_security_fields();

create table if not exists public.account_security_events(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_type text not null check(event_type in('login_success','logout','password_changed','sessions_revoked','email_verification_sent','account_data_exported')),
 user_agent text,
 created_at timestamptz not null default now()
);
create index if not exists account_security_events_user_created_idx on public.account_security_events(user_id,created_at desc);
alter table public.account_security_events enable row level security;
drop policy if exists "Users read own security events" on public.account_security_events;
create policy "Users read own security events" on public.account_security_events for select to authenticated using(user_id=auth.uid());
drop policy if exists "Administrators read security events" on public.account_security_events;
create policy "Administrators read security events" on public.account_security_events for select to authenticated using(public.is_active_marketplace_admin());
revoke all on public.account_security_events from anon,public;
grant select on public.account_security_events to authenticated;

create or replace function public.log_account_security_event(p_event_type text,p_user_agent text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if p_event_type not in('login_success','logout','password_changed','sessions_revoked','email_verification_sent','account_data_exported') then raise exception 'Unsupported security event.'; end if;
 insert into public.account_security_events(user_id,event_type,user_agent) values(auth.uid(),p_event_type,left(coalesce(p_user_agent,''),300)) returning id into v_id;
 return v_id;
end;
$$;
revoke all on function public.log_account_security_event(text,text) from public,anon;
grant execute on function public.log_account_security_event(text,text) to authenticated;

alter table public.user_blocks enable row level security;
drop policy if exists "Users read their own blocks" on public.user_blocks;
create policy "Users read their own blocks" on public.user_blocks for select to authenticated using(blocker_id=auth.uid());
drop policy if exists "Users create their own blocks" on public.user_blocks;
create policy "Users create their own blocks" on public.user_blocks for insert to authenticated with check(blocker_id=auth.uid() and blocked_id<>auth.uid());
drop policy if exists "Users remove their own blocks" on public.user_blocks;
create policy "Users remove their own blocks" on public.user_blocks for delete to authenticated using(blocker_id=auth.uid());
drop policy if exists "Administrators review user blocks" on public.user_blocks;
create policy "Administrators review user blocks" on public.user_blocks for select to authenticated using(public.is_active_marketplace_admin());
grant select,insert,delete on public.user_blocks to authenticated;
