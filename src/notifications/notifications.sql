-- Marketplace notification system. Run once after payments.sql and message.sql.
create extension if not exists pgcrypto;

alter table public.marketplace_notifications add column if not exists action_url text;
alter table public.marketplace_notifications add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.marketplace_notifications add column if not exists priority text not null default 'normal' check(priority in('low','normal','high'));

create index if not exists marketplace_notifications_unread_idx on public.marketplace_notifications(user_id,created_at desc) where read_at is null;

create table if not exists public.notification_preferences(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 in_app_enabled boolean not null default true,
 email_enabled boolean not null default false,
 push_enabled boolean not null default false,
 order_updates boolean not null default true,
 payment_updates boolean not null default true,
 messages boolean not null default true,
 product_alerts boolean not null default true,
 promotions boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.notification_preferences enable row level security;
drop policy if exists "Users read own notification preferences" on public.notification_preferences;
create policy "Users read own notification preferences" on public.notification_preferences for select to authenticated using(user_id=auth.uid());
drop policy if exists "Users insert own notification preferences" on public.notification_preferences;
create policy "Users insert own notification preferences" on public.notification_preferences for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "Users update own notification preferences" on public.notification_preferences;
create policy "Users update own notification preferences" on public.notification_preferences for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select,insert,update on public.notification_preferences to authenticated;

create table if not exists public.product_availability_subscriptions(
 customer_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(customer_id,product_id)
);
alter table public.product_availability_subscriptions enable row level security;
drop policy if exists "Customers manage own product availability subscriptions" on public.product_availability_subscriptions;
create policy "Customers manage own product availability subscriptions" on public.product_availability_subscriptions for all to authenticated
using(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='customer' and is_active))
with check(customer_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and role='customer' and is_active));
grant select,insert,delete on public.product_availability_subscriptions to authenticated;

create or replace function public.create_marketplace_notification(
 p_user_id uuid,p_type text,p_title text,p_message text,p_related_id uuid default null,p_action_url text default null,p_priority text default 'normal',p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if p_user_id is null or not exists(select 1 from public.profiles where id=p_user_id and is_active=true) then return null; end if;
 if exists(select 1 from public.notification_preferences where user_id=p_user_id and in_app_enabled=false) then return null; end if;
 insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id,action_url,priority,metadata)
 values(p_user_id,left(p_type,80),left(p_title,160),left(p_message,1000),p_related_id,p_action_url,coalesce(p_priority,'normal'),coalesce(p_metadata,'{}'::jsonb))
 returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.create_marketplace_notification(uuid,text,text,text,uuid,text,text,jsonb) from public,anon,authenticated;

create or replace function public.notify_marketplace_order() returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text; v_order text;
begin
 v_order:=coalesce(new.order_number,'Order '||left(new.id::text,8));
 if tg_op='INSERT' then
  perform public.create_marketplace_notification(new.seller_id,'new_order','New order received',v_order||' has been placed. Review and process the order.',new.id,'/seller', 'high',jsonb_build_object('order_number',v_order));
  if new.customer_id is not null and not exists(select 1 from public.seller_orders o where o.seller_id=new.seller_id and o.customer_id=new.customer_id and o.id<>new.id) then
   select coalesce(full_name,'A new customer') into v_name from public.profiles where id=new.customer_id;
   perform public.create_marketplace_notification(new.seller_id,'new_customer','New customer',coalesce(v_name,'A new customer')||' placed their first order with your store.',new.customer_id,'/seller','normal','{}'::jsonb);
  end if;
  return new;
 end if;
 if new.status is distinct from old.status then
  if new.status='confirmed' then perform public.create_marketplace_notification(new.customer_id,'order_confirmed','Order confirmed',v_order||' has been confirmed by the seller.',new.id,'/orders','normal','{}'::jsonb);
  elsif new.status in('shipped','ready_for_delivery') then perform public.create_marketplace_notification(new.customer_id,'order_delivery','Order on the way',v_order||' is now '||replace(new.status,'_',' ')||'.',new.id,'/orders','normal','{}'::jsonb);
  elsif new.status='delivered' then perform public.create_marketplace_notification(new.customer_id,'order_delivered','Order delivered',v_order||' has been marked as delivered.',new.id,'/orders','normal','{}'::jsonb);
  elsif new.status='cancelled' then perform public.create_marketplace_notification(new.customer_id,'order_cancelled','Order cancelled',v_order||' has been cancelled.',new.id,'/orders','high','{}'::jsonb);
  elsif new.status='refunded' then perform public.create_marketplace_notification(new.customer_id,'order_refunded','Order refunded',v_order||' has been marked as refunded.',new.id,'/orders','normal','{}'::jsonb);
  end if;
 end if;
 if new.payment_status is distinct from old.payment_status then
  if new.payment_status='paid' then
   perform public.create_marketplace_notification(new.customer_id,'payment_success','Payment confirmed','Payment for '||v_order||' was successful.',new.id,'/transactions','high','{}'::jsonb);
   perform public.create_marketplace_notification(new.seller_id,'payment_received','Payment received','Payment for '||v_order||' has been verified.',new.id,'/seller','normal','{}'::jsonb);
  elsif new.payment_status='failed' then perform public.create_marketplace_notification(new.customer_id,'payment_failed','Payment failed','Payment for '||v_order||' was unsuccessful. You can retry from your orders.',new.id,'/orders','high','{}'::jsonb);
  end if;
 end if;
 return new;
end; $$;
drop trigger if exists marketplace_order_notifications on public.seller_orders;
create trigger marketplace_order_notifications after insert or update of status,payment_status on public.seller_orders for each row execute function public.notify_marketplace_order();

create or replace function public.notify_marketplace_message() returns trigger language plpgsql security definer set search_path=public as $$
declare v_recipient uuid; v_sender text;
begin
 select case when c.customer_id=new.sender_id then c.seller_id else c.customer_id end
 into v_recipient from public.conversations c where c.id=new.conversation_id;
 select coalesce(full_name,'A marketplace user') into v_sender from public.profiles where id=new.sender_id;
 if v_recipient is not null then
  perform public.create_marketplace_notification(v_recipient,'new_message','New message',v_sender||' sent you a message.',new.conversation_id,'/messages','normal','{}'::jsonb);
 end if;
 return new;
end; $$;
drop trigger if exists marketplace_message_notifications on public.messages;
create trigger marketplace_message_notifications after insert on public.messages for each row execute function public.notify_marketplace_message();

create or replace function public.notify_product_stock() returns trigger language plpgsql security definer set search_path=public as $$
declare v_product text; v_sub record;
begin
 if tg_op='UPDATE' and new.stock<=5 and old.stock>5 and new.is_active and new.status='published' and new.visibility='public' then
  perform public.create_marketplace_notification(new.seller_id,'low_stock','Low stock alert',coalesce(new.name,new.title,'A product')||' has only '||new.stock||' unit(s) left.',new.id,'/seller','high',jsonb_build_object('stock',new.stock));
 end if;
 if tg_op='UPDATE' and old.stock=0 and new.stock>0 and new.is_active and new.status='published' and new.visibility='public' then
  v_product:=coalesce(new.name,new.title,'A product');
  for v_sub in select customer_id from public.product_availability_subscriptions where product_id=new.id loop
   perform public.create_marketplace_notification(v_sub.customer_id,'product_available','Product back in stock',v_product||' is available again.',new.id,'/product/'||new.id::text,'normal','{}'::jsonb);
  end loop;
 end if;
 return new;
end; $$;
drop trigger if exists marketplace_product_stock_notifications on public.products;
create trigger marketplace_product_stock_notifications after update of stock on public.products for each row execute function public.notify_product_stock();

create or replace function public.notify_marketplace_promotion() returns trigger language plpgsql security definer set search_path=public as $$
declare v_customer record; v_changed boolean:=false;
begin
 if tg_op='INSERT' then v_changed:=true;
 else v_changed:=old.is_active is distinct from new.is_active or old.title is distinct from new.title or old.subtitle is distinct from new.subtitle or old.image_url is distinct from new.image_url or old.cta_url is distinct from new.cta_url;
 end if;
 if new.is_active and (new.starts_at is null or new.starts_at<=now()) and (new.ends_at is null or new.ends_at>now()) and v_changed then
  for v_customer in select id from public.profiles where role='customer' and is_active loop
   perform public.create_marketplace_notification(v_customer.id,'promotion','New marketplace promotion',new.title||coalesce(': '||new.subtitle,''),new.id,coalesce(new.cta_url,'/'),'low','{}'::jsonb);
  end loop;
 end if;
 return new;
end; $$;
drop trigger if exists marketplace_promotion_notifications on public.promotional_banners;
create trigger marketplace_promotion_notifications after insert or update on public.promotional_banners for each row execute function public.notify_marketplace_promotion();

do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='marketplace_notifications') then
  execute 'alter publication supabase_realtime add table public.marketplace_notifications';
 end if;
end $$;

-- The client may only change read_at; notification creation is trigger/service controlled.
revoke insert,update,delete on public.marketplace_notifications from authenticated;
grant select on public.marketplace_notifications to authenticated;
grant update(read_at) on public.marketplace_notifications to authenticated;
