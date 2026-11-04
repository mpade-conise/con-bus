import{Navigate}from"react-router-dom";import{useAuth}from"./AuthContext.jsx";
export default function RoleBasedAccess({allow,children}){const{role,loading}=useAuth();if(loading)return <div className="auth-loading">Checking permissions…</div>;return allow.includes(role)?children:<Navigate to="/" replace/>;}
