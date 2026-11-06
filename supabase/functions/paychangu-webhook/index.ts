import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const hex=bytes=>Array.from(new Uint8Array(bytes)).map(b=>b.toString(16).padStart(2,"0")).join("");
const safeEqual=(a,b)=>{if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0};
const currency=value=>["MK","MWK"].includes(String(value||"").toUpperCase())?"MWK":String(value||"").toUpperCase();
Deno.serve(async req=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 try{
  const raw=await req.text(),signature=req.headers.get("Signature")||req.headers.get("signature")||"",webhookSecret=Deno.env.get("PAYCHANGU_WEBHOOK_SECRET");
  if(!webhookSecret||!signature)return new Response("Webhook signature missing",{status:401});
  const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(webhookSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const expected=hex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(raw)));
  if(!safeEqual(expected.toLowerCase(),signature.trim().toLowerCase()))return new Response("Invalid signature",{status:401});
  const event=JSON.parse(raw),txRef=event.tx_ref||event.data?.tx_ref||event.charge_id||event.data?.charge_id||event.data?.transaction?.charge_id;
  if(!txRef)return new Response("Transaction reference missing",{status:400});
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),secret=Deno.env.get("PAYCHANGU_SECRET_KEY");
  if(!url||!service||!secret)throw new Error("Payment service is not configured.");
  const db=createClient(url,service);
  const{data:tx,error:lookupError}=await db.from("marketplace_transactions").select("id,tx_ref,amount,currency,status,payment_method,provider_charge_id").eq("tx_ref",txRef).maybeSingle();
  if(lookupError)throw lookupError;if(!tx)return new Response("Unknown transaction",{status:404});
  if(tx.status==="successful")return new Response("Already processed",{status:200});
  if(tx.status!=="pending")return new Response("Transaction is no longer pending",{status:200});
  const mobile=tx.payment_method!=="card",chargeId=tx.provider_charge_id||tx.tx_ref;
  const endpoint=mobile?"https://api.paychangu.com/mobile-money/payments/"+encodeURIComponent(chargeId)+"/verify":"https://api.paychangu.com/verify-payment/"+encodeURIComponent(tx.tx_ref);
  const verifyResponse=await fetch(endpoint,{headers:{"Accept":"application/json","Authorization":"Bearer "+secret}});
  const verification=await verifyResponse.json().catch(()=>({})),payment=verification?.data?.transaction||verification?.data;
  const status=String(payment?.status||verification?.status||"").toLowerCase();
  if(!verifyResponse.ok||!["success","successful"].includes(status)){
   if(["failed","cancelled","canceled","expired"].includes(status))await db.rpc("fail_marketplace_payment",{p_tx_ref:tx.tx_ref,p_reason:verification?.message||"Provider reports payment was not completed."});
   return new Response("Payment is not yet confirmed",{status:200});
  }
  const providerCharge=String(payment?.charge_id||payment?.tx_ref||chargeId);
  if(providerCharge!==chargeId||currency(payment?.currency)!=="MWK"||Number(payment?.amount)!==Number(tx.amount)){
   await db.from("payment_reconciliation").insert({transaction_id:tx.id,tx_ref:tx.tx_ref,provider_reference:payment?.ref_id||payment?.reference||null,expected_amount:tx.amount,received_amount:Number(payment?.amount)||null,currency:payment?.currency||null,result:"mismatch",notes:"Webhook verification did not match the expected charge, amount or currency."});
   return new Response("Payment mismatch flagged for reconciliation",{status:202});
  }
  const{error:finalizeError}=await db.rpc("finalize_marketplace_payment",{p_tx_ref:tx.tx_ref,p_provider_reference:String(payment?.ref_id||payment?.reference||payment?.trans_id||""),p_amount:Number(payment.amount),p_currency:"MWK",p_provider_status:"success",p_provider_fee:Number(payment?.transaction_charges?.amount||payment?.charges||payment?.charge||0)});
  if(finalizeError)throw finalizeError;
  return new Response("Payment verified",{status:200});
 }catch(error){return new Response(error?.message||"Webhook processing failed",{status:500})}
});