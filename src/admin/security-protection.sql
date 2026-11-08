-- Con-Bus login abuse protection. Safe to run repeatedly.
alter table public.failed_login_attempts add column if not exists account_key text;
create index if not exists failed_login_attempts_account_recent_idx on public.failed_login_attempts(account_key,created_at desc) where account_key is not null;
create index if not exists failed_login_attempts_ip_recent_idx on public.failed_login_attempts(client_ip,created_at desc) where client_ip is not null;

create table if not exists public.login_lockouts(
  lockout_type text not null check(lockout_type in('account','ip')),
  identifier_hash text not null,
  client_ip text,
  locked_until timestamptz not null,
  created_at timestamptz not null default now(),
  primary key(lockout_type,identifier_hash)
);
alter table public.login_lockouts enable row level security;
revoke all on public.login_lockouts from public,anon,authenticated;
grant select,insert,update,delete on public.login_lockouts to service_role;
