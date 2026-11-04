import{Routes,Route}from"react-router-dom";import{StorefrontProvider}from"./StorefrontContext.jsx";import Homepage from"./Homepage.jsx";import ProductDetails from"./ProductDetails.jsx";
export default function HomepageRouter(){return <StorefrontProvider><Routes><Route path="/" element={<Homepage/>}/><Route path="/product/:id" element={<ProductDetails/>}/></Routes></StorefrontProvider>}
