import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const normalizeCurrency=value=>["MK","MWK"].includes(String(value||"").toUpperCase())?"MWK":String(value||"").toUpperCase();
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed."},405);
 try{
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),secret=Deno.env.get("PAYCHANGU_SECRET_KEY");
  if(!url||!anon||!service||!secret)throw new Error("Payment service is not configured.");
  const authorization=req.headers.get("Authorization");if(!authorization?.startsWith("Bearer "))return json({error:"Authentication required."},401);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
  const{data:{user},error:userError}=await userClient.auth.getUser();if(userError||!user)return json({error:"Invalid session."},401);
  const{tx_ref}=await req.json();if(typeof tx_ref!=="string"||!tx_ref.startsWith("MH-"))return json({error:"Invalid transaction reference."},400);
  const db=createClient(url,service);
  const{data:tx,error:lookupError}=await db.from("marketplace_transactions").select("id,tx_ref,customer_id,amount,currency,status,payment_method,provider_charge_id").eq("tx_ref",tx_ref).eq("customer_id",user.id).maybeSingle();
  if(lookupError)throw lookupError;if(!tx)return json({error:"Transaction not found."},404);
  if(tx.status!=="pending")return json({status:tx.status});
  const mobile=tx.payment_method!=="card",chargeId=tx.provider_charge_id||tx.tx_ref;
  const endpoint=mobile?"https://api.paychangu.com/mobile-money/payments/"+encodeURIComponent(chargeId)+"/verify":"https://api.paychangu.com/verify-payment/"+encodeURIComponent(tx_ref);
  const response=await fetch(endpoint,{headers:{"Accept":"application/json","Authorization":"Bearer "+secret}});
  const result=await response.json().catch(()=>({})),payment=result?.data?.transaction||result?.data;
  if(!response.ok)return json({status:"pending",message:result?.message||"Provider has not returned a final status."});
  const providerStatus=String(payment?.status||result?.status||"").toLowerCase();
  if(["success","successful"].includes(providerStatus)){
   const paidRef=String(payment?.charge_id||payment?.tx_ref||chargeId);
   const currency=normalizeCurrency(payment?.currency);
   if(paidRef!==chargeId||currency!=="MWK"||Number(payment?.amount)!==Number(tx.amount)){
    await db.from("payment_reconciliation").insert({transaction_id:tx.id,tx_ref,provider_reference:payment?.ref_id||payment?.reference||null,expected_amount:tx.amount,received_amount:Number(payment?.amount)||null,currency:payment?.currency||null,result:"mismatch",notes:"Verified PayChangu details did not match the expected charge, amount or currency."});
    return json({status:"pending",message:"Payment is under manual reconciliation."},202);
   }
   const{error}=await db.rpc("finalize_marketplace_payment",{p_tx_ref:tx_ref,p_provider_reference:String(payment?.ref_id||payment?.reference||payment?.trans_id||""),p_amount:Number(payment.amount),p_currency:"MWK",p_provider_status:"success",p_provider_fee:Number(payment?.transaction_charges?.amount||payment?.charges||payment?.charge||0)});if(error)throw error;
   return json({status:"successful"});
  }
  if(["failed","cancelled","canceled","expired"].includes(providerStatus)){
   const{error}=await db.rpc("fail_marketplace_payment",{p_tx_ref:tx_ref,p_reason:result?.message||"Payment was not completed."});if(error)throw error;
   return json({status:"failed"});
  }
  return json({status:"pending",message:"Approve the payment on your phone to complete checkout."});
 }catch(error){return json({error:error?.message||"Unable to verify payment."},500)}
});