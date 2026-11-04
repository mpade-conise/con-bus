import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed."},405);
 try{
  const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,secret=Deno.env.get("PAYCHANGU_SECRET_KEY")!,appUrl=Deno.env.get("APP_URL")!;
  if(!url||!anon||!service||!secret||!appUrl)throw new Error("Payment service is not configured.");
  const auth=req.headers.get("Authorization");if(!auth?.startsWith("Bearer "))return json({error:"Authentication required."},401);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const{data:{user},error:userError}=await userClient.auth.getUser();if(userError||!user)return json({error:"Your session is invalid. Sign in again."},401);
  const body=await req.json();const orderIds=body.order_ids;const method=body.method;
  if(!Array.isArray(orderIds)||!orderIds.length||orderIds.length>30||!["airtel_money","tnm_mpamba","card"].includes(method))return json({error:"Invalid order or payment method."},400);
  const{data:intent,error:intentError}=await userClient.rpc("create_marketplace_payment_intent",{p_order_ids:orderIds,p_method:method});
  if(intentError)throw intentError;
  const serviceClient=createClient(url,service);
  const callbackUrl=url+"/functions/v1/payment-callback";
  const payload={amount:String(intent.amount),currency:"MWK",email:intent.email||user.email||"",first_name:intent.first_name||"Customer",last_name:intent.last_name||"",callback_url:callbackUrl,return_url:appUrl.replace(/\/$/,"")+"/payment-result?tx_ref="+encodeURIComponent(intent.tx_ref),tx_ref:intent.tx_ref,customization:{title:"Marketplace order payment",description:"Payment for marketplace order(s)"},meta:{customer_id:user.id,transaction_id:intent.transaction_id,preferred_method:method,order_ids:orderIds}};
  const response=await fetch("https://api.paychangu.com/payment",{method:"POST",headers:{"Accept":"application/json","Content-Type":"application/json","Authorization":"Bearer "+secret},body:JSON.stringify(payload)});
  const result=await response.json().catch(()=>({}));
  const checkoutUrl=result?.data?.checkout_url;const providerIntent=result?.data?.data;
  if(!response.ok||result?.status!=="success"||providerIntent?.tx_ref!==intent.tx_ref||Number(providerIntent?.amount)!==Number(intent.amount)||String(providerIntent?.currency).toUpperCase()!=="MWK"||!checkoutUrl||!/^https:\/\/(checkout|test-checkout)\.paychangu\.com\//.test(checkoutUrl)){
   await serviceClient.rpc("fail_marketplace_payment",{p_tx_ref:intent.tx_ref,p_reason:result?.message||"PayChangu could not create checkout."});
   return json({error:result?.message||"Payment checkout could not be created.",tx_ref:intent.tx_ref},502);
  }
  const{error:updateError}=await serviceClient.from("marketplace_transactions").update({checkout_url:checkoutUrl,provider_status:"checkout_created",updated_at:new Date().toISOString()}).eq("id",intent.transaction_id);
  if(updateError)throw updateError;
  return json({checkout_url:checkoutUrl,tx_ref:intent.tx_ref,amount:intent.amount,currency:"MWK"});
 }catch(error){return json({error:error?.message||"Unable to start payment."},500)}
});
