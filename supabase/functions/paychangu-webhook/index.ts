import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const hex=bytes=>Array.from(new Uint8Array(bytes)).map(b=>b.toString(16).padStart(2,"0")).join("");
const safeEqual=(a,b)=>{if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0};
Deno.serve(async req=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 try{
  const raw=await req.text();const signature=req.headers.get("Signature")||req.headers.get("signature")||"";
  const secret=Deno.env.get("PAYCHANGU_WEBHOOK_SECRET");if(!secret||!signature)return new Response("Webhook signature missing",{status:401});
  const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const expected=hex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(raw)));
  if(!safeEqual(expected.toLowerCase(),signature.trim().toLowerCase()))return new Response("Invalid signature",{status:401});
  const event=JSON.parse(raw);const txRef=event.tx_ref||event.data?.tx_ref||event.meta?.tx_ref;
  if(!txRef)return new Response("Transaction reference missing",{status:400});
  const url=Deno.env.get("SUPABASE_URL")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,secretKey=Deno.env.get("PAYCHANGU_SECRET_KEY")!;
  const db=createClient(url,service);
  const{data:tx,error:lookupError}=await db.from("marketplace_transactions").select("id,tx_ref,amount,currency,status").eq("tx_ref",txRef).maybeSingle();
  if(lookupError)throw lookupError;if(!tx)return new Response("Unknown transaction",{status:404});
  if(tx.status==="successful")return new Response("Already processed",{status:200});
  if(tx.status!=="pending")return new Response("Transaction is no longer pending",{status:200});
  const verifyResponse=await fetch("https://api.paychangu.com/verify-payment/"+encodeURIComponent(txRef),{headers:{"Accept":"application/json","Authorization":"Bearer "+secretKey}});
  const verification=await verifyResponse.json().catch(()=>({}));
  const payment=verification?.data;
  if(!verifyResponse.ok||verification?.status!=="success"||payment?.status!=="success"){
   await db.rpc("fail_marketplace_payment",{p_tx_ref:txRef,p_reason:verification?.message||"Provider verification did not confirm payment."});
   return new Response("Payment not successful",{status:200});
  }
  if(payment.tx_ref!==txRef||String(payment.currency).toUpperCase()!=="MWK"||Number(payment.amount)!==Number(tx.amount)){
   await db.from("payment_reconciliation").insert({transaction_id:tx.id,tx_ref:txRef,provider_reference:payment.reference||null,expected_amount:tx.amount,received_amount:Number(payment.amount)||null,currency:payment.currency||null,result:"mismatch",notes:"Verified provider details did not match the local transaction."});
   return new Response("Payment details mismatch; flagged for reconciliation",{status:202});
  }
  const{error:finalizeError}=await db.rpc("finalize_marketplace_payment",{p_tx_ref:txRef,p_provider_reference:String(payment.reference||""),p_amount:Number(payment.amount),p_currency:String(payment.currency).toUpperCase(),p_provider_status:payment.status,p_provider_fee:Number(payment.charges||payment.charge||0)});
  if(finalizeError)throw finalizeError;
  return new Response("Payment verified",{status:200});
 }catch(error){return new Response(error?.message||"Webhook processing failed",{status:500})}
});
