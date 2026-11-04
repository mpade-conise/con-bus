import{Navigate}from"react-router-dom";import{useAuth}from"./AuthContext.jsx";
export default function ProtectedRoute({children,roles}){const{user,role,loading}=useAuth();if(loading)return <div className="auth-loading">Loading your account…</div>;if(!user)return <Navigate to="/auth/login" replace/>;if(roles&&!roles.includes(role))return <Navigate to="/" replace/>;return children;}
