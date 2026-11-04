import{Navigate,Routes,Route}from"react-router-dom";
import{StorefrontProvider}from"./homepage/StorefrontContext.jsx";
import{authRoutes}from"./authentication/auth.jsx";
import{homepageRoutes}from"./homepage/homepage.jsx";
import{sellerRoutes}from"./sellers/sellers.jsx";
import{adminRoutes}from"./admin/admin.jsx";
import Messaging from"./messaging/Messaging.jsx";
import ProtectedRoute from"./authentication/ProtectedRoute.jsx";

export default function App(){
 return <StorefrontProvider><Routes>{[...authRoutes,...homepageRoutes,...sellerRoutes,...adminRoutes,<Route key="messages" path="/messages" element={<ProtectedRoute roles={["customer","seller"]}><Messaging/></ProtectedRoute>}/>,<Route key="not-found" path="*" element={<Navigate to="/auth/login" replace/>}/>]}</Routes></StorefrontProvider>;
}