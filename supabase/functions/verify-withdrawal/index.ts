import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const validCurrency=v=>["MWK","MK"].includes(String(v||"").toUpperCase());
const normalizeStatus=v=>{const s=String(v||"").toLowerCase();if(["success","successful","succeeded","paid","completed"].includes(s))return"succeeded";if(["failed","failure","rejected","cancelled"].includes(s))return"failed";if(["pending","processing","initiated","queued"].includes(s))return"pending";return"unknown"};
const getTransaction=result=>[result?.data?.transaction,result?.data?.data?.transaction,result?.data,result?.transaction,result?.result?.transaction,result?.result?.data,result?.result,result].find(v=>v&&typeof v==="object"&&!Array.isArray(v)&&("charge_id"in v||"chargeId"in v||"amount"in v||"status"in v))||null;
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed."},405);
 try{
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),secret=Deno.env.get("PAYCHANGU_SECRET_KEY");
  if(!url||!anon||!service||!secret)throw new Error("Withdrawal verification is not configured.");
  const authorization=req.headers.get("Authorization");if(!authorization?.startsWith("Bearer "))return json({error:"Authentication required."},401);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
  const{data:{user},error:userError}=await userClient.auth.getUser();if(userError||!user)return json({error:"Your session is invalid. Sign in again."},401);
  const adminClient=createClient(url,service);
  const{data:profile,error:profileError}=await adminClient.from("profiles").select("role,is_active").eq("id",user.id).maybeSingle();
  if(profileError||profile?.role!=="administrator"||profile?.is_active!==true)return json({error:"Active administrator access required."},403);
  const body=await req.json(),withdrawalId=String(body.withdrawal_id||"");
  if(!/^[0-9a-f-]{36}$/i.test(withdrawalId))return json({error:"A valid withdrawal ID is required."},400);
  const{data:w,error:wError}=await adminClient.from("seller_withdrawals").select("id,reference,amount,currency,payout_method,status,provider_reference").eq("id",withdrawalId).maybeSingle();
  if(wError||!w)return json({error:"Withdrawal request not found."},404);
  const{data:attempt,error:attemptError}=await adminClient.from("seller_withdrawal_payout_attempts").select("id,charge_id,status,provider_reference,provider_status").eq("withdrawal_id",withdrawalId).maybeSingle();
  if(attemptError)throw attemptError;
  if(!attempt)return json({error:"No automated payout attempt exists for this withdrawal."},404);
  if(["succeeded","failed"].includes(attempt.status))return json({status:attempt.status,provider_reference:attempt.provider_reference||w.provider_reference,message:"This payout has already been finalized."});
  if(w.status!=="processing")return json({error:"Only processing withdrawals can be verified.",status:w.status},409);
  const path=w.payout_method==="bank_transfer"?"/direct-charge/payouts/"+encodeURIComponent(attempt.charge_id)+"/details":"/mobile-money/payments/"+encodeURIComponent(attempt.charge_id)+"details";
  const response=await fetch("https://api.paychangu.com"+path,{headers:{Accept:"application/json",Authorization:"Bearer "+secret},signal:AbortSignal.timeout(20000)});
  const result=await response.json().catch(()=>({})),data=getTransaction(result);
  const providerChargeId=String(data?.charge_id??data?.chargeId??"");
  const providerAmount=Number(data?.amount);
  const providerCurrency=String(data?.currency||"").toUpperCase();
  const mismatches=[];
  if(!response.ok)mismatches.push("http_"+response.status);
  if(!data)mismatches.push("missing_transaction_data");
  if(data&&providerChargeId!==attempt.charge_id)mismatches.push("charge_id_mismatch");
  if(data&&(!Number.isFinite(providerAmount)||providerAmount!==Number(w.amount)))mismatches.push("amount_mismatch");
  if(data&&!validCurrency(providerCurrency))mismatches.push("currency_mismatch");
  if(mismatches.length){
   const providerStatus="verification_mismatch:"+mismatches.join(",");
   const{error:updateError}=await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:attempt.charge_id,p_status:"unknown",p_provider_status:providerStatus,p_failure_reason:null});
   if(updateError)throw updateError;
   return json({status:"unknown",verification:mismatches,message:"PayChangu's response could not be matched safely. The withdrawal remains processing; do not submit it again."},202);
  }
  const providerStatus=String(data.status||result.status||"unknown"),s=normalizeStatus(providerStatus);
  const finalStatus=s==="succeeded"?"succeeded":s==="failed"?"failed":s==="pending"?"pending":"unknown";
  const providerReference=data.ref_id||data.reference||attempt.provider_reference||null;
  const{error:updateError}=await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:attempt.charge_id,p_status:finalStatus,p_provider_reference:providerReference,p_provider_status:providerStatus,p_failure_reason:finalStatus==="failed"?"PayChangu confirmed that the payout failed.":null});
  if(updateError)throw updateError;
  return json({status:finalStatus,provider_reference:providerReference,message:finalStatus==="succeeded"?"PayChangu confirmed the transfer.":finalStatus==="failed"?"PayChangu confirmed that the transfer failed.":"PayChangu has not yet confirmed final settlement."},finalStatus==="pending"||finalStatus==="unknown"?202:200);
 }catch(error){return json({error:error?.message||"Unable to verify seller payout."},500)}
});