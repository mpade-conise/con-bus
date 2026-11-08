import{createClient}from"https://esm.sh/@supabase/supabase-js@2";
const PAYOUTS_ENABLED=false;
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const operators={airtel_money:"20be6c20-adeb-4b5b-a7ba-0769820df4fb",tnm_mpamba:"27494cb5-ba9e-437f-a114-4e7a7686bcca"};
const validCurrency=v=>["MWK","MK"].includes(String(v||"").toUpperCase());
const normalizeStatus=v=>{const s=String(v||"").toLowerCase();if(["success","successful","succeeded","paid","completed"].includes(s))return"succeeded";if(["failed","failure","rejected","cancelled"].includes(s))return"failed";if(["pending","processing","initiated","queued"].includes(s))return"pending";return"unknown"};
async function verifyProvider(secret,method,chargeId,amount){
 const path=method==="bank_transfer"?"/direct-charge/payouts/"+encodeURIComponent(chargeId)+"/details":"/mobile-money/payments/"+encodeURIComponent(chargeId)+"/details";
 const response=await fetch("https://api.paychangu.com"+path,{headers:{Accept:"application/json",Authorization:"Bearer "+secret}});
 const result=await response.json().catch(()=>({})),data=result?.data?.transaction||result?.data;
 if(!response.ok||!data||String(data.charge_id||"")!==chargeId||Number(data.amount)!==Number(amount)||!validCurrency(data.currency))return{status:"unknown",providerStatus:data?.status||result?.status||"verification_mismatch",providerReference:data?.ref_id||null};
 return{status:normalizeStatus(data.status),providerStatus:String(data.status||result.status||"unknown"),providerReference:data.ref_id||data.reference||null};
}
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed."},405);
 try{
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),secret=Deno.env.get("PAYCHANGU_SECRET_KEY");
  if(!url||!anon||!service||!secret)throw new Error("Withdrawal service is not configured.");
  if(!PAYOUTS_ENABLED||Deno.env.get("PAYCHANGU_PAYOUTS_ENABLED")!=="true")return json({error:"PayChangu payouts are not enabled for this merchant account. No payout was submitted."},503);
  const authorization=req.headers.get("Authorization");if(!authorization?.startsWith("Bearer "))return json({error:"Authentication required."},401);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
  const{data:{user},error:userError}=await userClient.auth.getUser();if(userError||!user)return json({error:"Your session is invalid. Sign in again."},401);
  const adminClient=createClient(url,service);
  const{data:profile,error:profileError}=await adminClient.from("profiles").select("role,is_active").eq("id",user.id).maybeSingle();
  if(profileError||profile?.role!=="administrator"||profile?.is_active!==true)return json({error:"Active administrator access required."},403);
  const body=await req.json(),withdrawalId=String(body.withdrawal_id||"");
  if(!/^[0-9a-f-]{36}$/i.test(withdrawalId))return json({error:"A valid withdrawal ID is required."},400);
  const{data:w,error:wError}=await adminClient.from("seller_withdrawals").select("id,reference,seller_id,amount,currency,payout_method,destination,status").eq("id",withdrawalId).maybeSingle();
  if(wError||!w)return json({error:"Withdrawal request not found."},404);
  if(w.currency!=="MWK"||Number(w.amount)<=0)return json({error:"Withdrawal amount or currency is invalid."},400);
  const destination=w.destination||{},name=String(destination.account_name||"").trim(),account=String(destination.account_number||"").trim();
  if(!name||!account)return json({error:"The saved payout destination is incomplete."},400);
  let payload,endpoint;
  if(w.payout_method==="airtel_money"||w.payout_method==="tnm_mpamba"){
   const mobile=account.replace(/[\s()-]/g,"");
   if(!/^\+?(?:265)?0?\d{9}$/.test(mobile))return json({error:"The saved mobile number is not a valid Malawi number. No payout was submitted."},400);
   endpoint="/mobile-money/payouts/initialize";
   payload={mobile,mobile_money_operator_ref_id:operators[w.payout_method],amount:String(w.amount),charge_id:w.reference};
  }else if(w.payout_method==="bank_transfer"){
   if(!/^[0-9a-f-]{36}$/i.test(String(destination.bank_uuid||"")))return json({error:"This bank destination has no PayChangu bank UUID. Bank payout automation is not configured for this saved destination."},400);
   endpoint="/direct-charge/payouts/initialize";
   payload={payout_method:"bank_transfer",bank_uuid:destination.bank_uuid,amount:String(w.amount),charge_id:w.reference,bank_account_name:name,bank_account_number:account};
  }else return json({error:"Unsupported payout method."},400);
  const{data:claim,error:claimError}=await adminClient.rpc("claim_seller_withdrawal_payout",{p_withdrawal_id:withdrawalId,p_charge_id:w.reference});
  if(claimError)throw claimError;
  if(!claim?.claimed)return json({message:"This withdrawal already has a payout attempt. Check its status; it will not be submitted again.",status:claim?.status,provider_reference:claim?.provider_reference},200);
  let response,result;
  try{
   response=await fetch("https://api.paychangu.com"+endpoint,{method:"POST",headers:{Accept:"application/json","Content-Type":"application/json",Authorization:"Bearer "+secret},body:JSON.stringify(payload),signal:AbortSignal.timeout(25000)});
   result=await response.json().catch(()=>({}));
  }catch(error){
   await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:w.reference,p_status:"unknown",p_provider_status:"network_error",p_failure_reason:"The payout request outcome is unknown. Verify with PayChangu before taking any further action."});
   return json({message:"PayChangu did not return a conclusive response. The withdrawal remains processing to prevent a duplicate transfer. Check payout status before retrying.",status:"unknown"},202);
  }
  const data=result?.data?.transaction||result?.data;
  const responseCharge=String(data?.charge_id||"");
  const responseMatches=responseCharge===w.reference&&Number(data?.amount)===Number(w.amount)&&validCurrency(data?.currency);
  if(!response.ok||result?.status!=="success"){
   const definitive=response.status>=400&&response.status<500;
   const state=definitive?"failed":"unknown";
   await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:w.reference,p_status:state,p_provider_reference:data?.ref_id||null,p_provider_status:String(data?.status||result?.status||"request_rejected"),p_failure_reason:String(result?.message||"PayChangu payout request was not accepted.")});
   return json({error:result?.message||"PayChangu did not accept the payout request.",status:state},definitive?502:202);
  }
  if(!responseMatches){
   await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:w.reference,p_status:"unknown",p_provider_reference:data?.ref_id||null,p_provider_status:String(data?.status||"response_mismatch"),p_failure_reason:"Provider response did not match the requested charge ID, amount or currency. Manual verification is required."});
   return json({message:"PayChangu returned a response that could not be matched safely. The withdrawal remains processing; do not submit it again.",status:"unknown"},202);
  }
  const initialStatus=normalizeStatus(data.status);
  if(initialStatus==="failed"){
   await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:w.reference,p_status:"failed",p_provider_reference:data.ref_id||null,p_provider_status:String(data.status),p_failure_reason:"PayChangu reported that the payout failed."});
   return json({message:"PayChangu reported a failed payout.",status:"failed"},200);
  }
  const checked=await verifyProvider(secret,w.payout_method,w.reference,w.amount).catch(()=>({status:"unknown",providerStatus:"verification_unavailable",providerReference:data.ref_id||null}));
  const finalStatus=checked.status==="succeeded"?"succeeded":checked.status==="failed"?"failed":checked.status==="pending"?"pending":"unknown";
  const{error:updateError}=await adminClient.rpc("update_seller_withdrawal_payout_attempt",{p_charge_id:w.reference,p_status:finalStatus,p_provider_reference:checked.providerReference||data.ref_id||null,p_provider_status:checked.providerStatus,p_failure_reason:finalStatus==="failed"?"PayChangu confirmed that the payout failed.":null});
  if(updateError)throw updateError;
  return json({message:finalStatus==="succeeded"?"PayChangu verified the payout successfully.":finalStatus==="failed"?"PayChangu verified that the payout failed.":"Payout request submitted. The provider has not yet confirmed final settlement.",status:finalStatus,provider_reference:checked.providerReference||data.ref_id||null},202);
 }catch(error){return json({error:error?.message||"Unable to initiate seller payout."},500)}
});