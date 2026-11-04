import{createContext,useContext,useEffect,useMemo,useState}from"react";import{requireSupabase,supabase,isSupabaseConfigured}from"../authentication/supabase.js";import{useAuth}from"../authentication/AuthContext.jsx";
const StorefrontContext=createContext(null);
const read=(key)=>{try{const value=JSON.parse(localStorage.getItem(key)||"[]");return Array.isArray(value)?value:[]}catch{return[]}};
const itemFrom=p=>({id:p.id,name:p.name||p.title||"Product",price:Number(p.discount_price??p.sale_price??p.price??0),originalPrice:Number(p.price??0),image:p.image_url||p.image||(Array.isArray(p.images)?(typeof p.images[0]==="string"?p.images[0]:p.images[0]?.url):"")||"",quantity:1,stock:Number(p.stock??0),availability_status:p.availability_status||"available",seller_id:p.seller_id});
export function StorefrontProvider({children}){const{user,loading:authLoading}=useAuth();const[products,setProducts]=useState([]);const[loading,setLoading]=useState(true);const[error,setError]=useState("");const[cart,setCart]=useState(()=>read("market-hub-cart"));const[savedItems,setSavedItems]=useState(()=>read("market-hub-saved"));
useEffect(()=>{localStorage.setItem("market-hub-cart",JSON.stringify(cart))},[cart]);useEffect(()=>{localStorage.setItem("market-hub-saved",JSON.stringify(savedItems))},[savedItems]);
useEffect(()=>{let active=true;if(authLoading)return()=>{active=false};if(!user){setProducts([]);setError("");setLoading(false);return()=>{active=false}}setLoading(true);(async()=>{if(!isSupabaseConfigured){setLoading(false);return}try{const{data,error}=await supabase.from("products").select("*").limit(120);if(error)throw error;if(active)setProducts((data||[]).filter(p=>p.is_active===true&&p.status==="published"&&p.visibility!=="private"));}catch(e){if(active)setError(e.message)}finally{if(active)setLoading(false)}})();return()=>{active=false}},[user?.id,authLoading]);
const addToCart=product=>{if(!product||product.availability_status==="out_of_stock"||Number(product.stock??0)<=0)return false;setCart(old=>{const id=String(product.id),found=old.find(x=>String(x.id)===id);if(found)return old.map(x=>String(x.id)===id?{...x,quantity:Math.min(Number(x.stock??product.stock??99),x.quantity+1)}:x);return[...old,itemFrom(product)]});return true};
const changeQuantity=(id,quantity)=>setCart(old=>quantity<1?old.filter(x=>String(x.id)!==String(id)):old.map(x=>String(x.id)===String(id)?{...x,quantity:Math.min(Number(x.stock??99),Math.max(1,Math.floor(Number(quantity)||1)))}:x));
const removeFromCart=id=>setCart(old=>old.filter(x=>String(x.id)!==String(id)));
const saveForLater=id=>{const item=cart.find(x=>String(x.id)===String(id));if(!item)return;setSavedItems(old=>old.some(x=>String(x.id)===String(id))?old:[...old,item]);removeFromCart(id)};
const moveToCart=id=>{const item=savedItems.find(x=>String(x.id)===String(id));if(!item)return;setCart(old=>old.some(x=>String(x.id)===String(id))?old: [...old,{...item,quantity:Math.min(item.quantity,Number(item.stock??99))}]);setSavedItems(old=>old.filter(x=>String(x.id)!==String(id)))};
const removeSaved=id=>setSavedItems(old=>old.filter(x=>String(x.id)!==String(id)));
const clearCart=()=>setCart([]);
const cartSubtotal=cart.reduce((n,x)=>n+Number(x.originalPrice??x.price)*Number(x.quantity||0),0);
const cartDiscount=cart.reduce((n,x)=>n+Math.max(0,Number(x.originalPrice??x.price)-Number(x.price))*Number(x.quantity||0),0);
const cartTotal=cartSubtotal-cartDiscount;
const cartCount=cart.reduce((n,x)=>n+Number(x.quantity||0),0);
const value=useMemo(()=>({products,setProducts,loading,error,cart,savedItems,addToCart,changeQuantity,removeFromCart,saveForLater,moveToCart,removeSaved,clearCart,cartCount,cartSubtotal,cartDiscount,cartTotal,deliveryFee:null,grandTotal:null}),[products,loading,error,cart,savedItems,cartCount,cartSubtotal,cartDiscount,cartTotal]);
return <StorefrontContext.Provider value={value}>{children}</StorefrontContext.Provider>}
export function useStorefront(){const v=useContext(StorefrontContext);if(!v)throw Error("useStorefront must be inside StorefrontProvider");return v}
export const money=value=>new Intl.NumberFormat("en-MW",{style:"currency",currency:"MWK",maximumFractionDigits:0}).format(Number(value)||0);
export const productName=p=>p.name||p.title||"Untitled product";export const productImage=p=>p.image_url||p.image||(Array.isArray(p.images)?(typeof p.images[0]==="string"?p.images[0]:p.images[0]?.url):"")||"";export const productPrice=p=>Number(p.discount_price??p.sale_price??p.price??0);export const productCategory=p=>p.category_name||p.category?.name||p.category||"Other";
