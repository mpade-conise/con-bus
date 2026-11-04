import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const html=(target,status=200)=>new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="0;url=${target}"><title>Returning to marketplace</title></head><body><p>Returning to your order… <a href="${target}">Continue</a></p><script>location.replace(${JSON.stringify(target)})</script></body></html>`,{status,headers:{"Content-Type":"text/html; charset=utf-8","Cache-Control":"no-store"}});
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});
const hex=bytes=>Array.from(new Uint8Array(bytes)).map(b=>b.toString(16).padStart(2,"0")).join("");
const safeEqual=(a,b)=>{if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0};
async function readReference(req){
 const url=new URL(req.url);let ref=url.searchParams.get("tx_ref")||url.searchParams.get("reference");
 if(req.method==="GET")return ref;
 const raw=await req.text();if(!raw)return ref;
 let body;
 try{body=JSON.parse(raw)}catch{body=Object.fromEntries(new URLSearchParams(raw))}
 return ref||body?.tx_ref||body?.data?.tx_ref||body?.reference||body?.data?.reference||null;
}
Deno.serve(async req=>{
 if(!["GET","POST"].includes(req.method))return new Response("Method not allowed",{status:405});
 const appUrl=Deno.env.get("APP_URL");
 let target=appUrl?new URL("/payment-result",appUrl).toString():"/";
 try{
  const txRef=await readReference(req);
  if(!txRef||typeof txRef!=="string"||txRef.length>160)return json({error:"Transaction reference is missing or invalid."},400);
  const secret=Deno.env.get("PAYCHANGU_SECRET_KEY"),url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!secret||!url||!service||!appUrl)throw new Error("Payment callback is not configured.");
  const destination=new URL("/payment-result",appUrl);destination.searchParams.set("tx_ref",txRef);target=destination.toString();
  const signature=req.headers.get("Signature")||req.headers.get("signature");
  if(signature){
   const rawBody=await req.clone().text();
   const webhookSecret=Deno.env.get("PAYCHANGU_WEBHOOK_SECRET");
   if(!webhookSecret)return json({error:"Webhook signature validation is not configured."},503);
   const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(webhookSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
   const expected=hex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(rawBody)));
   if(!safeEqual(expected.toLowerCase(),signature.trim().toLowerCase()))return json({error:"Invalid payment signature."},401);
  }
  const db=createClient(url,service);
  const{data:tx,error:lookupError}=await db.from("marketplace_transactions").select("id,tx_ref,amount,currency,status").eq("tx_ref",txRef).maybeSingle();
  if(lookupError)throw lookupError;
  if(!tx)return html(target);
  if(tx.status==="pending"){
   const response=await fetch("https://api.paychangu.com/verify-payment/"+encodeURIComponent(txRef),{headers:{"Accept":"application/json","Authorization":"Bearer "+secret}});
   const result=await response.json().catch(()=>({}));const payment=result?.data;
   if(response.ok&&result?.status==="success"&&payment?.status==="success"){
    if(payment.tx_ref!==txRef||String(payment.currency).toUpperCase()!=="MWK"||Number(payment.amount)!==Number(tx.amount)){
     await db.from("payment_reconciliation").insert({transaction_id:tx.id,tx_ref:txRef,provider_reference:payment.reference||null,expected_amount:tx.amount,received_amount:Number(payment.amount)||null,currency:payment.currency||null,result:"mismatch",notes:"Payment callback verification did not match the expected reference, amount or currency."});
    }else{
     const{error}=await db.rpc("finalize_marketplace_payment",{p_tx_ref:txRef,p_provider_reference:String(payment.reference||""),p_amount:Number(payment.amount),p_currency:String(payment.currency).toUpperCase(),p_provider_status:payment.status,p_provider_fee:Number(payment.charges||payment.charge||0)});
     if(error)throw error;
    }
   }else if(response.ok&&["failed","cancelled","canceled","expired"].includes(String(payment?.status||"").toLowerCase())){
    await db.rpc("fail_marketplace_payment",{p_tx_ref:txRef,p_reason:result?.message||"PayChangu reports that the payment was not completed."});
   }
  }
  return html(target);
 }catch(error){
  return appUrl?html(target,200):json({error:error?.message||"Payment callback failed."},500);
 }
});