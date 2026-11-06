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
