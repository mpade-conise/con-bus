import{Navigate,Route,Routes}from"react-router-dom";
import AuthRouter from"./authentication/auth.jsx";
import HomepageRouter from"./homepage/homepage.jsx";
import SellersRouter from"./sellers/sellers.jsx";

export default function App(){
  return <><HomepageRouter/><AuthRouter/><SellersRouter/><Routes><Route path="*" element={<Navigate to="/auth/login" replace/>}/></Routes></>;
}
