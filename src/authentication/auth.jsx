import{Route}from"react-router-dom";
import Login from"./Login.jsx";
import CustomerRegistration from"./CustomerRegistration.jsx";
import SellerRegistration from"./SellerRegistration.jsx";
import EmailVerification from"./EmailVerification.jsx";
import PhoneVerification from"./PhoneVerification.jsx";
import ForgotPassword from"./ForgotPassword.jsx";
import ResetPassword from"./ResetPassword.jsx";
import ProfileManagement from"./ProfileManagement.jsx";
import ProfilePictureUpload from"./ProfilePictureUpload.jsx";
import ChangePassword from"./ChangePassword.jsx";
import AccountDeactivation from"./AccountDeactivation.jsx";
import Logout from"./Logout.jsx";
import ProtectedRoute from"./ProtectedRoute.jsx";
import DeactivatedAccount from"./DeactivatedAccount.jsx";
import Dashboard from"./Dashboard.jsx";
import SecurityCenter from"./SecurityCenter.jsx";

export const authRoutes=[
 <Route key="login" path="/auth/login" element={<Login/>}/>,
 <Route key="register-customer" path="/auth/register/customer" element={<CustomerRegistration/>}/>,
 <Route key="register-seller" path="/auth/register/seller" element={<SellerRegistration/>}/>,
 <Route key="verify-email" path="/auth/verify-email" element={<EmailVerification/>}/>,
 <Route key="verify-phone" path="/auth/verify-phone" element={<ProtectedRoute><PhoneVerification/></ProtectedRoute>}/>,
 <Route key="forgot-password" path="/auth/forgot-password" element={<ForgotPassword/>}/>,
 <Route key="reset-password" path="/auth/reset-password" element={<ResetPassword/>}/>,
 <Route key="dashboard" path="/dashboard" element={<ProtectedRoute><Dashboard/></ProtectedRoute>}/>,
 <Route key="deactivated" path="/account/deactivated" element={<DeactivatedAccount/>}/>,
 <Route key="profile" path="/account/profile" element={<ProtectedRoute><ProfileManagement/></ProtectedRoute>}/>,
 <Route key="profile-picture" path="/account/profile-picture" element={<ProtectedRoute><ProfilePictureUpload/></ProtectedRoute>}/>,
 <Route key="change-password" path="/account/change-password" element={<ProtectedRoute><ChangePassword/></ProtectedRoute>}/>,
 <Route key="account-security" path="/account/security" element={<ProtectedRoute><SecurityCenter/></ProtectedRoute>}/>,
 <Route key="deactivate" path="/account/deactivate" element={<ProtectedRoute><AccountDeactivation/></ProtectedRoute>}/>,
 <Route key="logout" path="/auth/logout" element={<ProtectedRoute><Logout/></ProtectedRoute>}/>
];
