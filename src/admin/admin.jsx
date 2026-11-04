import{Routes,Route}from"react-router-dom";import ProtectedRoute from"../authentication/ProtectedRoute.jsx";import PaymentsAdmin from"./PaymentsAdmin.jsx";
export default function AdminRouter(){return <Routes><Route path="/admin/payments" element={<ProtectedRoute roles={["administrator"]}><PaymentsAdmin/></ProtectedRoute>}/></Routes>}
