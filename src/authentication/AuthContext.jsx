import { createContext, useContext, useEffect, useState } from "react";
import { requireSupabase, supabase, isSupabaseConfigured } from "./supabase.js";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [session,setSession]=useState(null);
  const [profile,setProfile]=useState(null);
  const [loading,setLoading]=useState(true);

  async function loadProfile(user) {
    if (!user || !isSupabaseConfigured) { setProfile(null); return; }
    const {data}=await supabase.from("profiles").select("*").eq("id",user.id).maybeSingle();
    setProfile(data || {id:user.id,email:user.email,role:"customer"});
  }

  useEffect(()=>{
    if (!isSupabaseConfigured) { setLoading(false); return; }
    let alive=true;
    supabase.auth.getSession().then(async({data})=>{if(!alive)return;setSession(data.session);await loadProfile(data.session?.user);if(alive)setLoading(false);});
    const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>{setSession(next);if(!next)setProfile(null);else queueMicrotask(()=>loadProfile(next.user));});
    return()=>{alive=false;subscription.unsubscribe();};
  },[]);

  async function signOut(){const client=requireSupabase();const {error}=await client.auth.signOut();if(error)throw error;setSession(null);setProfile(null);}
  async function refreshProfile(){await loadProfile(session?.user);}
  return <AuthContext.Provider value={{session,user:session?.user || null,profile,role:profile?.role || null,loading,configured:isSupabaseConfigured,signOut,refreshProfile}}>{children}</AuthContext.Provider>;
}

export function useAuth(){const value=useContext(AuthContext);if(!value)throw new Error("useAuth must be used inside AuthProvider");return value;}
