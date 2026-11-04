import{Route}from"react-router-dom";import ProtectedRoute from"../authentication/ProtectedRoute.jsx";import SellerDashboard from"./SellerDashboard.jsx";
export const sellerRoutes=[<Route key="seller" path="/seller/*" element={<ProtectedRoute roles={["seller"]}><SellerDashboard/></ProtectedRoute>}/>];
