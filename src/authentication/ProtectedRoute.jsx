import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "./AuthContext.jsx";

export default function ProtectedRoute({children,roles}) {
  const {user,role,profile,loading,configured}=useAuth();
  const location=useLocation();
  if(!configured)return <div className="auth-loading">Sign-in is temporarily unavailable. Please try again later.</div>;
  if(loading)return <div className="auth-loading">Verifying your login session…</div>;
  if(!user)return <Navigate to="/auth/login" replace state={{from:location.pathname+location.search+location.hash}}/>;
  if(!profile)return <div className="auth-loading">Your account could not be verified. Please sign out and sign in again.</div>;
  if(profile.is_active===false)return <Navigate to="/account/deactivated" replace/>;
  const portal=role==="seller"?"/seller":role==="customer"?"/":"/admin";
  if(location.pathname==="/dashboard"&&portal!=="/dashboard")return <Navigate to={portal} replace/>;
  if(roles&&!roles.includes(role))return <Navigate to={portal} replace/>;
  return children;
}
