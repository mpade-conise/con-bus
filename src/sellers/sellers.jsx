import{Routes,Route}from"react-router-dom";import ProtectedRoute from"../authentication/ProtectedRoute.jsx";import SellerDashboard from"./SellerDashboard.jsx";
export default function SellersRouter(){return <Routes><Route path="/seller/*" element={<ProtectedRoute roles={["seller"]}><SellerDashboard/></ProtectedRoute>}/></Routes>}
