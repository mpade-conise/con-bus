import { createContext, useContext, useEffect, useRef, useState } from "react";
import { requireSupabase, supabase, isSupabaseConfigured } from "./supabase.js";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [session,setSession]=useState(null);
  const [profile,setProfile]=useState(null);
  const [loading,setLoading]=useState(true);
  const requestId=useRef(0);

  async function loadProfile(user) {
    if (!user || !isSupabaseConfigured) return null;
    const {data,error}=await supabase.from("profiles").select("id,role,is_active").eq("id",user.id).maybeSingle();
    if (error) throw error;
    return data;
  }

  useEffect(()=>{
    if (!isSupabaseConfigured) { setLoading(false); return; }
    let alive=true;
    let authEventReceived=false;
    const syncSession=async(next)=>{
      const current=++requestId.current;
      setSession(next);
      setProfile(null);
      setLoading(true);
      if (!next?.user) { setLoading(false); return; }
      try {
        const data=await loadProfile(next.user);
        if (alive && current===requestId.current) setProfile(data);
      } catch {
        if (alive && current===requestId.current) setProfile(null);
      } finally {
        if (alive && current===requestId.current) setLoading(false);
      }
    };
    const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>{
      if (!alive) return;
      authEventReceived=true;
      queueMicrotask(()=>{if(alive)syncSession(next)});
    });
    supabase.auth.getSession().then(({data,error})=>{
      if (!alive || authEventReceived) return;
      if (error) { setSession(null);setProfile(null);setLoading(false);return; }
      syncSession(data.session);
    }).catch(()=>{
      if(alive&&!authEventReceived){setSession(null);setProfile(null);setLoading(false);}
    });
    return()=>{alive=false;requestId.current++;subscription.unsubscribe();};
  },[]);

  async function signOut(){
    const client=requireSupabase();
    const {error}=await client.auth.signOut();
    if(error)throw error;
    setSession(null);
    setProfile(null);
  }
  async function refreshProfile(){
    const data=await loadProfile(session?.user);
    setProfile(data);
    return data;
  }
  return <AuthContext.Provider value={{session,user:session?.user||null,profile,role:profile?.role||null,loading,configured:isSupabaseConfigured,signOut,refreshProfile}}>{children}</AuthContext.Provider>;
}

export function useAuth(){
  const value=useContext(AuthContext);
  if(!value)throw new Error("useAuth must be used inside AuthProvider");
  return value;
}
