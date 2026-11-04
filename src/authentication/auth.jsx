import { Routes, Route } from "react-router-dom";
import Home from "../Home.jsx";
import Login from "./Login.jsx";
import CustomerRegistration from "./CustomerRegistration.jsx";
import SellerRegistration from "./SellerRegistration.jsx";
import EmailVerification from "./EmailVerification.jsx";
import PhoneVerification from "./PhoneVerification.jsx";
import ForgotPassword from "./ForgotPassword.jsx";
import ResetPassword from "./ResetPassword.jsx";
import ProfileManagement from "./ProfileManagement.jsx";
import ProfilePictureUpload from "./ProfilePictureUpload.jsx";
import ChangePassword from "./ChangePassword.jsx";
import AccountDeactivation from "./AccountDeactivation.jsx";
import Logout from "./Logout.jsx";
import ProtectedRoute from "./ProtectedRoute.jsx";

export default function AuthRouter() {
  return <Routes>
    <Route path="/" element={<Home/>}/>
    <Route path="/auth/login" element={<Login/>}/>
    <Route path="/auth/register/customer" element={<CustomerRegistration/>}/>
    <Route path="/auth/register/seller" element={<SellerRegistration/>}/>
    <Route path="/auth/verify-email" element={<EmailVerification/>}/>
    <Route path="/auth/verify-phone" element={<ProtectedRoute><PhoneVerification/></ProtectedRoute>}/>
    <Route path="/auth/forgot-password" element={<ForgotPassword/>}/>
    <Route path="/auth/reset-password" element={<ResetPassword/>}/>
    <Route path="/account/profile" element={<ProtectedRoute><ProfileManagement/></ProtectedRoute>}/>
    <Route path="/account/profile-picture" element={<ProtectedRoute><ProfilePictureUpload/></ProtectedRoute>}/>
    <Route path="/account/change-password" element={<ProtectedRoute><ChangePassword/></ProtectedRoute>}/>
    <Route path="/account/deactivate" element={<ProtectedRoute><AccountDeactivation/></ProtectedRoute>}/>
    <Route path="/auth/logout" element={<ProtectedRoute><Logout/></ProtectedRoute>}/>
    <Route path="*" element={<Home/>}/>
  </Routes>;
}
