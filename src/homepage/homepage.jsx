import{Route}from"react-router-dom";
import Homepage from"./Homepage.jsx";
import CustomerDashboard from"./CustomerDashboard.jsx";
import CustomerSupport from"./CustomerSupport.jsx";
import ProductDetails from"./ProductDetails.jsx";
import CheckoutStart from"./CheckoutStart.jsx";
import CustomerOrders from"./CustomerOrders.jsx";
import CustomerTransactions from"./CustomerTransactions.jsx";
import PaymentResult from"./PaymentResult.jsx";import CustomerAddresses from"../delivery/CustomerAddresses.jsx";
import ProtectedRoute from"../authentication/ProtectedRoute.jsx";

export const homepageRoutes=[
 <Route key="customer-dashboard" path="/customer/dashboard" element={<ProtectedRoute roles={["customer"]}><CustomerDashboard/></ProtectedRoute>}/>,
 <Route key="customer-account" path="/account" element={<ProtectedRoute roles={["customer"]}><CustomerDashboard/></ProtectedRoute>}/>,
 <Route key="home" path="/" element={<ProtectedRoute roles={["customer"]}><Homepage/></ProtectedRoute>}/>,

 <Route key="product" path="/product/:id" element={<ProtectedRoute roles={["customer"]}><ProductDetails/></ProtectedRoute>}/>,
 <Route key="checkout" path="/checkout" element={<ProtectedRoute roles={["customer"]}><CheckoutStart/></ProtectedRoute>}/>,
 <Route key="customer-support" path="/support" element={<ProtectedRoute roles={["customer"]}><CustomerSupport/></ProtectedRoute>}/>,
 <Route key="orders" path="/orders" element={<ProtectedRoute roles={["customer"]}><CustomerOrders/></ProtectedRoute>}/>,
 <Route key="transactions" path="/transactions" element={<ProtectedRoute roles={["customer"]}><CustomerTransactions/></ProtectedRoute>}/>,
 <Route key="payment-result" path="/payment-result" element={<ProtectedRoute roles={["customer"]}><PaymentResult/></ProtectedRoute>}/>,
 <Route key="customer-addresses" path="/customer/addresses" element={<ProtectedRoute roles={["customer"]}><CustomerAddresses/></ProtectedRoute>}/>
];
