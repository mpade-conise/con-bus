import{Route}from"react-router-dom";import ProtectedRoute from"../authentication/ProtectedRoute.jsx";import PaymentsAdmin from"./PaymentsAdmin.jsx";
export const adminRoutes=[<Route key="admin-payments" path="/admin/payments" element={<ProtectedRoute roles={["administrator"]}><PaymentsAdmin/></ProtectedRoute>}/>];
