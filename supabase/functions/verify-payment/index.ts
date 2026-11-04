import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed."},405);
 try{
  const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,secret=Deno.env.get("PAYCHANGU_SECRET_KEY")!;
  const authorization=req.headers.get("Authorization");if(!authorization?.startsWith("Bearer "))return json({error:"Authentication required."},401);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
  const{data:{user},error:userError}=await userClient.auth.getUser();if(userError||!user)return json({error:"Invalid session."},401);
  const{tx_ref}=await req.json();if(typeof tx_ref!=="string"||!tx_ref.startsWith("MH-"))return json({error:"Invalid transaction reference."},400);
  const db=createClient(url,service);
  const{data:tx,error:lookupError}=await db.from("marketplace_transactions").select("id,tx_ref,customer_id,amount,currency,status").eq("tx_ref",tx_ref).eq("customer_id",user.id).maybeSingle();
  if(lookupError)throw lookupError;if(!tx)return json({error:"Transaction not found."},404);
  if(tx.status!=="pending")return json({status:tx.status});
  const response=await fetch("https://api.paychangu.com/verify-payment/"+encodeURIComponent(tx_ref),{headers:{"Accept":"application/json","Authorization":"Bearer "+secret}});
  const result=await response.json().catch(()=>({}));const payment=result?.data;
  if(!response.ok||result?.status!=="success")return json({status:"pending",message:result?.message||"Provider has not returned a final status."});
  if(payment?.status==="success"){
   if(payment.tx_ref!==tx_ref||String(payment.currency).toUpperCase()!=="MWK"||Number(payment.amount)!==Number(tx.amount)){
    await db.from("payment_reconciliation").insert({transaction_id:tx.id,tx_ref,provider_reference:payment.reference||null,expected_amount:tx.amount,received_amount:Number(payment.amount)||null,currency:payment.currency||null,result:"mismatch",notes:"Customer status check returned mismatched provider values."});
    return json({status:"pending",message:"Payment is under manual reconciliation."},202);
   }
   const{error}=await db.rpc("finalize_marketplace_payment",{p_tx_ref:tx_ref,p_provider_reference:String(payment.reference||""),p_amount:Number(payment.amount),p_currency:String(payment.currency).toUpperCase(),p_provider_status:payment.status});if(error)throw error;
   return json({status:"successful"});
  }
  if(["failed","cancelled","canceled"].includes(String(payment?.status||"").toLowerCase())){
   await db.rpc("fail_marketplace_payment",{p_tx_ref:tx_ref,p_reason:result?.message||"Payment was not completed."});
   return json({status:"failed"});
  }
  return json({status:"pending"});
 }catch(error){return json({error:error?.message||"Unable to verify payment."},500)}
});
