import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed."},405);
 try{
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return json({error:"Authentication service is unavailable."},503);
  const body=await req.json().catch(()=>null);
  const email=typeof body?.email==="string"?body.email.trim():"";
  const password=typeof body?.password==="string"?body.password:"";
  if(!email||email.length>254||!/^\S+@\S+\.\S+$/.test(email)||!password||password.length>1024)return json({error:"Enter a valid email address and password."},400);
  const response=await fetch(url+"/auth/v1/token?grant_type=password",{method:"POST",headers:{"apikey":anon,"Content-Type":"application/json"},body:JSON.stringify({email,password})});
  const result=await response.json().catch(()=>({}));
  if(!response.ok){
   if(response.status===400||response.status===401){
    const db=createClient(url,service);
    const forwarded=req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    const clientIp=req.headers.get("x-real-ip")||forwarded||null;
    await db.from("failed_login_attempts").insert({client_ip:clientIp?.slice(0,64)||null,user_agent:req.headers.get("user-agent")?.slice(0,300)||null,failure_code:"invalid_credentials"});
   }
   return json({error:response.status===429?"Too many sign-in attempts. Please wait and try again.":"Invalid email or password."},response.status===429?429:401);
  }
  return json({access_token:result.access_token,refresh_token:result.refresh_token,token_type:result.token_type,expires_in:result.expires_in,expires_at:result.expires_at,user:result.user});
 }catch{
  return json({error:"Unable to sign in right now. Please try again."},503);
 }
});
