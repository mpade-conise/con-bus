import{useEffect,useState}from"react";import{useNavigate}from"react-router-dom";import{useAuth}from"./AuthContext.jsx";
export default function Logout(){const{signOut}=useAuth();const nav=useNavigate();const[e,E]=useState("");useEffect(()=>{signOut().then(()=>nav("/",{replace:true})).catch(x=>E(x.message));},[]);return <div className="auth-loading">{e||"Signing you out…"}</div>;}
