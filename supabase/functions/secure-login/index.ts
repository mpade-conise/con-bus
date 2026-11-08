import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
const WINDOW_MINUTES=15;
const ACCOUNT_LIMIT=5;
const IP_LIMIT=10;
const LOCKOUT_MINUTES=15;
const encoder=new TextEncoder();

async function fingerprint(value:string,secret:string){
  const key=await crypto.subtle.importKey("raw",encoder.encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const signature=await crypto.subtle.sign("HMAC",key,encoder.encode(value));
  return Array.from(new Uint8Array(signature),b=>b.toString(16).padStart(2,"0")).join("");
}

async function activeLockout(db:any,type:string,key:string){
  const {data,error}=await db.from("login_lockouts").select("locked_until").eq("lockout_type",type).eq("identifier_hash",key).gt("locked_until",new Date().toISOString()).maybeSingle();
  if(error)throw error;
  return data?.locked_until||null;
}

async function countRecent(db:any,column:string,value:string,cutoff:string){
  const {count,error}=await db.from("failed_login_attempts").select("id",{count:"exact",head:true}).eq(column,value).gte("created_at",cutoff);
  if(error)throw error;
  return count||0;
}

async function applyLockout(db:any,type:string,key:string,ip:string|null,count:number,threshold:number){
  if(count<threshold)return;
  const now=new Date(),until=new Date(now.getTime()+LOCKOUT_MINUTES*60_000).toISOString();
  const {error}=await db.from("login_lockouts").upsert({lockout_type:type,identifier_hash:key,client_ip:ip,locked_until:until,created_at:now.toISOString()},{onConflict:"lockout_type,identifier_hash"});
  if(error)throw error;
  const {data:prior,error:lookupError}=await db.from("admin_alerts").select("id").eq("alert_type",type+"_login_lockout").eq("source_record_id",key).gte("created_at",new Date(now.getTime()-LOCKOUT_MINUTES*60_000).toISOString()).limit(1);
  if(lookupError)throw lookupError;
  if(!prior?.length){
    const {error:alertError}=await db.from("admin_alerts").insert({alert_type:type+"_login_lockout",severity:"warning",title:type==="account"?"Account temporarily locked":"IP address temporarily restricted",details:`${count} failed sign-in attempts within ${WINDOW_MINUTES} minutes. A ${LOCKOUT_MINUTES}-minute cooldown has been applied.`,source_table:"login_lockouts",source_record_id:key});
    if(alertError)throw alertError;
  }
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed."},405);
  try{
    const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!url||!anon||!service)return json({error:"Authentication service is unavailable."},503);
    const body=await req.json().catch(()=>null);
    const email=typeof body?.email==="string"?body.email.trim().toLowerCase():"";
    const password=typeof body?.password==="string"?body.password:"";
    if(!email||email.length>254||!/^\S+@\S+\.\S+$/.test(email)||!password||password.length>1024)return json({error:"Enter a valid email address and password."},400);

    const db=createClient(url,service);
    const accountKey=await fingerprint("account:"+email,service);
    const rawIp=req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()||null;
    const clientIp=rawIp?.slice(0,64)||null;
    const ipKey=clientIp?await fingerprint("ip:"+clientIp,service):null;
    const [accountLocked,ipLocked]=await Promise.all([activeLockout(db,"account",accountKey),ipKey?activeLockout(db,"ip",ipKey):Promise.resolve(null)]);
    if(accountLocked||ipLocked){
      const until=Math.max(accountLocked?new Date(accountLocked).getTime():0,ipLocked?new Date(ipLocked).getTime():0);
      return json({error:"Too many sign-in attempts. Please wait before trying again.",retry_after:Math.max(1,Math.ceil((until-Date.now())/1000))},429);
    }

    const response=await fetch(url+"/auth/v1/token?grant_type=password",{method:"POST",headers:{"apikey":anon,"Content-Type":"application/json"},body:JSON.stringify({email,password})});
    const result=await response.json().catch(()=>({}));
    if(!response.ok){
      if(response.status===400||response.status===401){
        const {error:insertError}=await db.from("failed_login_attempts").insert({client_ip:clientIp,user_agent:req.headers.get("user-agent")?.slice(0,300)||null,failure_code:"invalid_credentials",account_key:accountKey});
        if(insertError)throw insertError;
        const cutoff=new Date(Date.now()-WINDOW_MINUTES*60_000).toISOString();
        const accountCount=await countRecent(db,"account_key",accountKey,cutoff);
        if(accountCount>=ACCOUNT_LIMIT)await applyLockout(db,"account",accountKey,clientIp,accountCount,ACCOUNT_LIMIT);
        if(ipKey){
          const ipCount=await countRecent(db,"client_ip",clientIp!,cutoff);
          if(ipCount>=IP_LIMIT)await applyLockout(db,"ip",ipKey,clientIp,ipCount,IP_LIMIT);
        }
      }
      return json({error:response.status===429?"Too many sign-in attempts. Please wait and try again.":"Invalid email or password."},response.status===429?429:401);
    }
    return json({access_token:result.access_token,refresh_token:result.refresh_token,token_type:result.token_type,expires_in:result.expires_in,expires_at:result.expires_at,user:result.user});
  }catch(error){
    console.error("secure-login error",error);
    return json({error:"Unable to sign in right now. Please try again."},503);
  }
});