create table if not exists public.failed_login_attempts (
 id uuid primary key default gen_random_uuid(),
 client_ip text,
 user_agent text,
 failure_code text not null default 'invalid_credentials',
 created_at timestamptz not null default now()
);
create index if not exists failed_login_attempts_created_idx on public.failed_login_attempts(created_at desc);
alter table public.failed_login_attempts add column if not exists alert_id uuid references public.admin_alerts(id) on delete set null;
alter table public.failed_login_attempts enable row level security;
drop policy if exists "Administrators read failed login attempts" on public.failed_login_attempts;
create policy "Administrators read failed login attempts" on public.failed_login_attempts for select to authenticated using (public.has_admin_permission('security.view'));

create or replace function public.create_failed_login_alert()
returns trigger language plpgsql security definer set search_path=public
as $function$
declare
 existing_alert uuid;
 attempt_count integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(coalesce(new.client_ip,'unknown'),0));
 select alert_id into existing_alert
 from public.failed_login_attempts
 where id<>new.id
  and client_ip is not distinct from new.client_ip
  and created_at>=now()-interval '15 minutes'
  and alert_id is not null
 order by created_at desc
 limit 1;
 if existing_alert is not null then
  select count(*) into attempt_count from public.failed_login_attempts where alert_id=existing_alert;
  update public.admin_alerts
  set title='Repeated failed sign-in attempts',
      details=format('%s unsuccessful sign-in attempts were recorded within the last 15 minutes%s.',attempt_count+1,case when nullif(new.client_ip,'') is null then '' else ' from IP '||new.client_ip end),
      source_record_id=new.id::text,created_at=now(),is_read=false,read_at=null
  where id=existing_alert;
 else
  insert into public.admin_alerts(alert_type,severity,title,details,source_table,source_record_id)
  values('account_security','warning','Failed sign-in attempt',
   format('An unsuccessful sign-in was recorded%s. Reason: %s',case when nullif(new.client_ip,'') is null then '' else ' from IP '||new.client_ip end,new.failure_code),
   'failed_login_attempts',new.id::text)
  returning id into existing_alert;
 end if;
 update public.failed_login_attempts set alert_id=existing_alert where id=new.id;
 return new;
end;
$function$;
drop trigger if exists failed_login_admin_alert on public.failed_login_attempts;
create trigger failed_login_admin_alert after insert on public.failed_login_attempts for each row execute function public.create_failed_login_alert();