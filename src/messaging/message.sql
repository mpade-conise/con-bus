-- Incremental messaging migration. Run this file once after the existing marketplace migrations.
create extension if not exists pgcrypto;

create table if not exists public.conversations (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.profiles(id) on delete cascade,
 seller_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid references public.products(id) on delete set null,
 customer_deleted_at timestamptz,
 seller_deleted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(customer_id<>seller_id)
);
create unique index if not exists conversations_pair_product_unique on public.conversations(customer_id,seller_id,coalesce(product_id,'00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists conversations_customer_updated_idx on public.conversations(customer_id,updated_at desc);
create index if not exists conversations_seller_updated_idx on public.conversations(seller_id,updated_at desc);

create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text,
 attachment_path text,
 attachment_name text,
 read_at timestamptz,
 created_at timestamptz not null default now(),
 check(nullif(trim(coalesce(body,'')),'') is not null or attachment_path is not null),
 check(length(coalesce(body,''))<=4000)
);
create index if not exists messages_conversation_created_idx on public.messages(conversation_id,created_at);
create index if not exists messages_unread_idx on public.messages(conversation_id,read_at) where read_at is null;

create table if not exists public.user_blocks (
 id uuid primary key default gen_random_uuid(),
 blocker_id uuid not null references public.profiles(id) on delete cascade,
 blocked_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique(blocker_id,blocked_id),
 check(blocker_id<>blocked_id)
);
create table if not exists public.message_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete cascade,
 message_id uuid not null references public.messages(id) on delete cascade,
 reason text not null,
 status text not null default 'pending' check(status in('pending','reviewed','dismissed','actioned')),
 created_at timestamptz not null default now(),
 unique(reporter_id,message_id)
);

create or replace function public.start_marketplace_conversation(p_other_user_id uuid,p_product_id uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();v_customer uuid;v_seller uuid;v_role text;v_id uuid;
begin
 if v_uid is null then raise exception 'Sign in to contact marketplace users.'; end if;
 select role into v_role from public.profiles where id=v_uid and is_active=true;
 if v_role not in('customer','seller') then raise exception 'Only customers and sellers can use marketplace messaging.'; end if;
 if v_role='customer' then v_customer:=v_uid;v_seller:=p_other_user_id;
 else v_seller:=v_uid;v_customer:=p_other_user_id; end if;
 if not exists(select 1 from public.profiles where id=case when v_role='customer' then v_seller else v_customer end and is_active=true and role=case when v_role='customer' then 'seller' else 'customer' end) then raise exception 'The selected marketplace user is unavailable.'; end if;
 if p_product_id is not null and not exists(select 1 from public.products where id=p_product_id and seller_id=v_seller and is_active and status='published' and visibility='public') then raise exception 'This product is no longer available.'; end if;
 if exists(select 1 from public.user_blocks where (blocker_id=v_customer and blocked_id=v_seller) or (blocker_id=v_seller and blocked_id=v_customer)) then raise exception 'Messaging is unavailable between these accounts.'; end if;
 insert into public.conversations(customer_id,seller_id,product_id) values(v_customer,v_seller,p_product_id)
 on conflict(customer_id,seller_id,(coalesce(product_id,'00000000-0000-0000-0000-000000000000'::uuid))) do update set customer_deleted_at=null,seller_deleted_at=null,updated_at=now()
 returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.start_marketplace_conversation(uuid,uuid) from public;
grant execute on function public.start_marketplace_conversation(uuid,uuid) to authenticated;

create or replace function public.touch_conversation_on_message()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 update public.conversations set updated_at=new.created_at,
 customer_deleted_at=case when customer_id=new.sender_id then null else customer_deleted_at end,
 seller_deleted_at=case when seller_id=new.sender_id then null else seller_deleted_at end
 where id=new.conversation_id;
 return new;
end; $$;
drop trigger if exists messages_touch_conversation on public.messages;
create trigger messages_touch_conversation after insert on public.messages for each row execute function public.touch_conversation_on_message();

alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.user_blocks enable row level security;
alter table public.message_reports enable row level security;

drop policy if exists "Conversation participants read conversations" on public.conversations;
create policy "Conversation participants read conversations" on public.conversations for select to authenticated using(customer_id=auth.uid() or seller_id=auth.uid());
drop policy if exists "Messaging participants read counterpart profiles" on public.profiles;
create policy "Messaging participants read counterpart profiles" on public.profiles for select to authenticated using(exists(select 1 from public.conversations c where (c.customer_id=auth.uid() and c.seller_id=profiles.id) or (c.seller_id=auth.uid() and c.customer_id=profiles.id)));
drop policy if exists "Conversation participants hide own conversations" on public.conversations;
create policy "Conversation participants hide own conversations" on public.conversations for update to authenticated using(customer_id=auth.uid() or seller_id=auth.uid()) with check(customer_id=auth.uid() or seller_id=auth.uid());

drop policy if exists "Conversation participants read messages" on public.messages;
create policy "Conversation participants read messages" on public.messages for select to authenticated using(exists(select 1 from public.conversations c where c.id=conversation_id and (c.customer_id=auth.uid() or c.seller_id=auth.uid())));
create or replace function public.marketplace_messaging_blocked(p_customer uuid,p_seller uuid) returns boolean language sql security definer set search_path=public as $
 select exists(select 1 from public.user_blocks where (blocker_id=p_customer and blocked_id=p_seller) or (blocker_id=p_seller and blocked_id=p_customer));
$;
revoke all on function public.marketplace_messaging_blocked(uuid,uuid) from public;
grant execute on function public.marketplace_messaging_blocked(uuid,uuid) to authenticated;

drop policy if exists "Participants send messages when not blocked" on public.messages;
create policy "Participants send messages when not blocked" on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.conversations c where c.id=conversation_id and (c.customer_id=auth.uid() or c.seller_id=auth.uid()) and not public.marketplace_messaging_blocked(c.customer_id,c.seller_id)));
drop policy if exists "Recipients mark messages read" on public.messages;
create policy "Recipients mark messages read" on public.messages for update to authenticated using(sender_id<>auth.uid() and exists(select 1 from public.conversations c where c.id=conversation_id and (c.customer_id=auth.uid() or c.seller_id=auth.uid()))) with check(sender_id<>auth.uid() and exists(select 1 from public.conversations c where c.id=conversation_id and (c.customer_id=auth.uid() or c.seller_id=auth.uid())));

drop policy if exists "Users manage blocks they create" on public.user_blocks;
create policy "Users manage blocks they create" on public.user_blocks for all to authenticated using(blocker_id=auth.uid()) with check(blocker_id=auth.uid());
drop policy if exists "Users report messages they receive" on public.message_reports;
create policy "Users report messages they receive" on public.message_reports for insert to authenticated with check(reporter_id=auth.uid() and exists(select 1 from public.messages m join public.conversations c on c.id=m.conversation_id where m.id=message_id and m.sender_id<>auth.uid() and (c.customer_id=auth.uid() or c.seller_id=auth.uid())));
drop policy if exists "Administrators review message reports" on public.message_reports;
create policy "Administrators review message reports" on public.message_reports for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='administrator' and p.is_active));

create or replace function public.guard_conversation_participant_update() returns trigger language plpgsql set search_path=public as $
begin
 if auth.uid()=old.customer_id then
  if new.customer_id is distinct from old.customer_id or new.seller_id is distinct from old.seller_id or new.product_id is distinct from old.product_id or new.seller_deleted_at is distinct from old.seller_deleted_at then raise exception 'You may only delete your own conversation view.'; end if;
 elsif auth.uid()=old.seller_id then
  if new.customer_id is distinct from old.customer_id or new.seller_id is distinct from old.seller_id or new.product_id is distinct from old.product_id or new.customer_deleted_at is distinct from old.customer_deleted_at then raise exception 'You may only delete your own conversation view.'; end if;
 else raise exception 'Not a conversation participant.'; end if;
 return new;
end; $;
drop trigger if exists guard_conversation_update on public.conversations;
create trigger guard_conversation_update before update on public.conversations for each row execute function public.guard_conversation_participant_update();

revoke update on public.conversations from authenticated;
grant select,update(customer_deleted_at,seller_deleted_at) on public.conversations to authenticated;
grant select,insert on public.messages to authenticated;
grant update(read_at) on public.messages to authenticated;
grant select,insert,delete on public.user_blocks to authenticated;
grant select,insert on public.message_reports to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('message-attachments','message-attachments',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','text/plain'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Conversation members upload message attachments" on storage.objects;
create policy "Conversation members upload message attachments" on storage.objects for insert to authenticated
with check(bucket_id='message-attachments' and (storage.foldername(name))[1] in(select c.id::text from public.conversations c where (c.customer_id=auth.uid() or c.seller_id=auth.uid()) and not public.marketplace_messaging_blocked(c.customer_id,c.seller_id)));
drop policy if exists "Conversation members read message attachments" on storage.objects;
create policy "Conversation members read message attachments" on storage.objects for select to authenticated
using(bucket_id='message-attachments' and (storage.foldername(name))[1] in(select c.id::text from public.conversations c where c.customer_id=auth.uid() or c.seller_id=auth.uid()));

do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then execute 'alter publication supabase_realtime add table public.messages'; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conversations') then execute 'alter publication supabase_realtime add table public.conversations'; end if;
 end if;
end $$;
