-- Auto-confirm cash-on-delivery orders at creation; confirm online orders only after verified payment.
create or replace function public.place_marketplace_order(
  p_items jsonb,p_delivery_address jsonb,p_delivery_method text,p_payment_method text,p_customer_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid(); v_seller uuid; v_product record; v_item jsonb; v_items jsonb;
  v_subtotal numeric(12,2); v_total numeric(12,2); v_grand_total numeric(12,2);
  v_order_id uuid; v_order_number text; v_result jsonb:='[]'::jsonb; v_qty integer; v_name text;
begin
  if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and role='customer' and is_active) then raise exception 'A verified customer account is required.'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Your cart is empty.'; end if;
  if (select count(*) from jsonb_array_elements(p_items))<>(select count(*) from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid) then raise exception 'One or more products in your cart no longer exist.'; end if;
  if coalesce(p_delivery_address->>'name','')='' or coalesce(p_delivery_address->>'phone','')='' or coalesce(p_delivery_address->>'city','')='' or coalesce(p_delivery_address->>'address','')='' then raise exception 'Enter the recipient name, phone, city and delivery address.'; end if;
  if p_delivery_method not in('home_delivery','pickup') then raise exception 'Choose a valid delivery method.'; end if;
  if p_payment_method not in('cash_on_delivery','airtel_money','tnm_mpamba','card') then raise exception 'Choose a valid payment method.'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where coalesce((i->>'quantity')::integer,0)<1) then raise exception 'Invalid product quantity.'; end if;
  for v_seller in select distinct p.seller_id from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid order by p.seller_id loop
    v_items:='[]'::jsonb; v_subtotal:=0; v_grand_total:=0;
    for v_item in select i from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid where p.seller_id=v_seller loop
      v_qty:=(v_item->>'quantity')::integer;
      select id,name,title,price,discount_price,sale_price,stock,is_active,status,visibility,seller_id into v_product from public.products where id=(v_item->>'id')::uuid for update;
      if not found or v_product.seller_id<>v_seller or not v_product.is_active or v_product.status<>'published' or v_product.visibility<>'public' then raise exception 'A selected product is no longer available.'; end if;
      if v_product.stock<v_qty then raise exception 'Insufficient stock for %.',coalesce(v_product.name,v_product.title); end if;
      v_name:=coalesce(v_product.name,v_product.title,'Product');
      v_total:=least(v_product.price,coalesce(v_product.discount_price,v_product.sale_price,v_product.price));
      v_subtotal:=v_subtotal+(v_product.price*v_qty); v_grand_total:=v_grand_total+(v_total*v_qty);
      v_items:=v_items||jsonb_build_array(jsonb_build_object('product_id',v_product.id,'name',v_name,'quantity',v_qty,'unit_price',v_total,'regular_price',v_product.price,'image_url',(select p.image_url from public.products p where p.id=v_product.id)));
      update public.products set stock=stock-v_qty where id=v_product.id;
    end loop;
    v_order_number:='MH-'||to_char(now(),'YYMMDD')||'-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8));
    insert into public.seller_orders(seller_id,customer_id,customer_name,order_number,items,subtotal,shipping_amount,discount_amount,total_amount,currency,status,payment_status,delivery_method,delivery_address,payment_method,customer_note)
    values(v_seller,v_uid,(select full_name from public.profiles where id=v_uid),v_order_number,v_items,v_subtotal,0,v_subtotal-v_grand_total,v_grand_total,'MWK',case when p_payment_method='cash_on_delivery' then 'confirmed' else 'pending' end,'pending',p_delivery_method,p_delivery_address,p_payment_method,nullif(p_customer_note,''))
    returning id into v_order_id;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('id',v_order_id,'order_number',v_order_number,'seller_id',v_seller,'total_amount',v_grand_total));
  end loop;
  if jsonb_array_length(v_result)=0 then raise exception 'No valid products were found in your cart.'; end if;
  return v_result;
end;
$$;
revoke all on function public.place_marketplace_order(jsonb,jsonb,text,text,text) from public;
grant execute on function public.place_marketplace_order(jsonb,jsonb,text,text,text) to authenticated;

create or replace function public.finalize_marketplace_payment(p_tx_ref text,p_provider_reference text,p_amount numeric,p_currency text,p_provider_status text,p_provider_fee numeric default 0)
returns void language plpgsql security definer set search_path=public as $$
declare v_tx public.marketplace_transactions%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required.'; end if;
  select * into v_tx from public.marketplace_transactions where tx_ref=p_tx_ref for update;
  if not found then raise exception 'Unknown transaction reference.'; end if;
  if v_tx.status='successful' then return; end if;
  if v_tx.status not in('pending','expired') then raise exception 'Transaction is not eligible for payment finalization.'; end if;
  if p_provider_status<>'success' or p_currency<>'MWK' or p_amount<>v_tx.amount then raise exception 'Provider payment details do not match the expected transaction.'; end if;
  if coalesce(p_provider_fee,0)<0 then raise exception 'Invalid provider fee.'; end if;
  if exists(select 1 from public.payment_order_allocations mine join public.payment_order_allocations other on other.order_id=mine.order_id join public.marketplace_transactions paid on paid.id=other.transaction_id where mine.transaction_id=v_tx.id and other.transaction_id<>v_tx.id and paid.status='successful') then
    update public.marketplace_transactions set status='refund_pending',provider_reference=p_provider_reference,provider_status='duplicate_payment_requires_refund',provider_fee=coalesce(p_provider_fee,0),updated_at=now() where id=v_tx.id;
    insert into public.payment_reconciliation(transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes)
    values(v_tx.id,v_tx.tx_ref,p_provider_reference,v_tx.amount,p_amount,p_currency,'duplicate_payment','Provider confirmed a second payment for orders already paid by another transaction. Refund this duplicate payment.');
    insert into public.marketplace_notifications(user_id,notification_type,title,message,related_id)
    values(v_tx.customer_id,'duplicate_payment','Duplicate payment under review','A second payment was detected for the same order. The extra payment is flagged for refund review.',v_tx.id);
    return;
  end if;
  update public.marketplace_transactions set status='successful',provider_reference=p_provider_reference,provider_status=p_provider_status,provider_fee=coalesce(p_provider_fee,0),completed_at=now(),updated_at=now() where id=v_tx.id;
  update public.marketplace_transactions other set status='expired',updated_at=now()
  where other.id<>v_tx.id and other.status='pending' and exists(select 1 from public.payment_order_allocations mine join public.payment_order_allocations theirs on theirs.order_id=mine.order_id where mine.transaction_id=v_tx.id and theirs.transaction_id=other.id);
  update public.seller_orders o set payment_status='paid',status=case when o.status='pending' then 'confirmed' else o.status end from public.payment_order_allocations a where a.transaction_id=v_tx.id and a.order_id=o.id;
  insert into public.seller_earnings(seller_id,order_id,transaction_id,gross_amount,platform_fee,net_amount)
  select seller_id,order_id,v_tx.id,gross_amount,platform_fee,seller_net from public.payment_order_allocations where transaction_id=v_tx.id
  on conflict(order_id) do nothing;
  insert into public.payment_reconciliation(transaction_id,tx_ref,provider_reference,expected_amount,received_amount,currency,result,notes)
  values(v_tx.id,v_tx.tx_ref,p_provider_reference,v_tx.amount,p_amount,p_currency,'matched','PayChangu verification succeeded.');
end;
$$;
revoke all on function public.finalize_marketplace_payment(text,text,numeric,text,text,numeric) from public;
grant execute on function public.finalize_marketplace_payment(text,text,numeric,text,text,numeric) to service_role;

-- Restore the delivery-aware checkout RPC used by the customer checkout UI.
-- Fix checkout: the customer explicitly selects one of the seller's active zones.
-- The selected zone is authoritative; do not reject it because typed address labels differ.
create or replace function public.place_marketplace_order_with_delivery(p_items jsonb,p_delivery_address jsonb,p_delivery_method text,p_payment_method text,p_customer_note text default null,p_delivery_zones jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_orders jsonb;v_order jsonb;v_final jsonb:='[]'::jsonb;v_zone_id uuid;v_zone public.seller_delivery_zones%rowtype;v_settings public.seller_delivery_settings%rowtype;v_fee numeric(12,2);v_eta timestamptz;v_location text;
begin
 if p_delivery_method not in('home_delivery','pickup') then raise exception 'Choose home delivery or pickup.';end if;
 v_orders:=public.place_marketplace_order(p_items,p_delivery_address,p_delivery_method,p_payment_method,p_customer_note);
 for v_order in select value from jsonb_array_elements(v_orders) loop
  select * into v_settings from public.seller_delivery_settings where seller_id=(v_order->>'seller_id')::uuid;
  if not found then v_settings.seller_id:=(v_order->>'seller_id')::uuid;v_settings.home_delivery_enabled:=true;v_settings.pickup_enabled:=true;v_settings.pickup_location:=null;v_settings.default_min_days:=1;v_settings.default_max_days:=3;end if;
  v_fee:=0;v_eta:=null;v_zone_id:=null;v_location:=null;
  if p_delivery_method='home_delivery' then
   if not v_settings.home_delivery_enabled then raise exception 'This seller does not currently offer home delivery.';end if;
   v_zone_id:=nullif(p_delivery_zones->>(v_order->>'seller_id'),'')::uuid;
   if v_zone_id is null then raise exception 'Select a delivery zone for every seller in your cart.';end if;
   select * into v_zone from public.seller_delivery_zones where id=v_zone_id and seller_id=(v_order->>'seller_id')::uuid and is_active;
   if not found then raise exception 'A selected delivery zone is no longer available.';end if;
   v_fee:=v_zone.delivery_fee;v_eta:=now()+make_interval(days=>ceil((v_zone.min_days+v_zone.max_days)::numeric/2)::integer);
  else
   if not v_settings.pickup_enabled then raise exception 'This seller does not currently offer pickup.';end if;
   v_location:=coalesce(nullif(trim(v_settings.pickup_location),''),'Pickup location to be confirmed by the seller');v_eta:=now()+make_interval(days=>ceil((v_settings.default_min_days+v_settings.default_max_days)::numeric/2)::integer);
  end if;
  update public.seller_orders set shipping_amount=v_fee,total_amount=total_amount+v_fee,delivery_zone_id=v_zone_id,delivery_status=case when p_delivery_method='pickup' then 'ready_for_pickup' else 'pending' end,estimated_delivery_at=v_eta,pickup_location=v_location,delivery_instructions=nullif(p_delivery_address->>'instructions','') where id=(v_order->>'id')::uuid;
  insert into public.seller_order_events(order_id,actor_id,event_type,note) values((v_order->>'id')::uuid,auth.uid(),'delivery_configured',case when p_delivery_method='pickup' then 'Pickup selected'||coalesce(': '||v_location,'') else 'Home delivery zone: '||v_zone.zone_name||'; fee MWK '||v_fee end);
  v_final:=v_final||jsonb_build_array(v_order||jsonb_build_object('delivery_fee',v_fee,'total_amount',(v_order->>'total_amount')::numeric+v_fee,'estimated_delivery_at',v_eta));
 end loop;
 return v_final;
end;$$;
revoke all on function public.place_marketplace_order_with_delivery(jsonb,jsonb,text,text,text,jsonb) from public,anon;
grant execute on function public.place_marketplace_order_with_delivery(jsonb,jsonb,text,text,text,jsonb) to authenticated;
revoke execute on function public.place_marketplace_order(jsonb,jsonb,text,text,text) from authenticated;
