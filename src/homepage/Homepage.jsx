import{useEffect,useMemo,useState}from"react";
import{useLocation,useNavigate}from"react-router-dom";
import{ArrowRight,MapPin,Store}from"lucide-react";
import{useStorefront,productCategory,productPrice,productName}from"./StorefrontContext.jsx";
import{supabase,isSupabaseConfigured}from"../authentication/supabase.js";
import StoreHeader from"./StoreHeader.jsx";
import HeroBanner from"./HeroBanner.jsx";
import PromotionalBanners from"./PromotionalBanners.jsx";
import ProductSearch from"./ProductSearch.jsx";
import ProductFilters from"./ProductFilters.jsx";
import ProductGrid from"./ProductGrid.jsx";
import QuickView from"./QuickView.jsx";
import CartDrawer from"./CartDrawer.jsx";

const readRecent=()=>{try{const v=JSON.parse(localStorage.getItem("market-hub-recent-searches")||"[]");return Array.isArray(v)?v:[]}catch{return[]}};
const uniqueProducts=(items,excluded=new Set())=>items.filter(p=>p?.id&&!excluded.has(String(p.id))).filter((p,i,a)=>a.findIndex(x=>String(x.id)===String(p.id))===i).slice(0,8);

export default function Homepage(){
 const{products,loading,error,addToCart}=useStorefront();
 const location=useLocation(),navigate=useNavigate(),params=new URLSearchParams(location.search);
 const[search,S]=useState(params.get("search")||""),[category,C]=useState(params.get("category")||"All category");
 const[min,Min]=useState(""),[max,Max]=useState(""),[availability,A]=useState("all"),[sort,Sort]=useState(params.get("sort")||"newest");
 const[locationFilter,LocationFilter]=useState(""),[rating,Rating]=useState("0"),[searchType,SearchType]=useState(params.get("type")||"all");
 const[sellerFilter,SellerFilter]=useState(params.get("seller")||""),[stores,Stores]=useState([]),[recent,Recent]=useState(readRecent),[quick,Q]=useState(null),[cartOpen,CO]=useState(false);
 useEffect(()=>{const p=new URLSearchParams(location.search);S(p.get("search")||"");C(p.get("category")||"All category");Sort(p.get("sort")||"newest");SearchType(p.get("type")||"all");SellerFilter(p.get("seller")||"")},[location.search]);
 useEffect(()=>{let active=true;if(!isSupabaseConfigured)return; (async()=>{const{data,error}=await supabase.from("seller_stores").select("seller_id,store_name,description,logo_url,city,region,country").eq("is_public",true);if(error||!active)return;const rows=data||[],ids=rows.map(s=>s.seller_id).filter(Boolean);if(!ids.length){Stores([]);return}const[profiles,delivery]=await Promise.all([supabase.from("profiles").select("id,full_name,avatar_url").in("id",ids),supabase.from("seller_delivery_settings").select("seller_id,home_delivery_enabled,pickup_enabled").in("seller_id",ids)]);if(!active)return;const profileMap=Object.fromEntries((profiles.data||[]).map(p=>[String(p.id),p])),deliveryMap=Object.fromEntries((delivery.data||[]).map(d=>[String(d.seller_id),d]));Stores(rows.map(s=>({...s,...profileMap[String(s.seller_id)],...(deliveryMap[String(s.seller_id)]||{})})))})();return()=>{active=false}},[]);
 const storeById=useMemo(()=>Object.fromEntries(stores.map(s=>[String(s.seller_id),s])),[stores]);
 const filtered=useMemo(()=>{
  let list=searchType==="seller"||searchType==="business"?[]:[...products],term=search.trim().toLowerCase();
  if(searchType!=="seller"&&searchType!=="business"&&term)list=list.filter(p=>[p.name,p.title,p.description,p.brand,p.store_name,p.seller_name,productCategory(p),(p.tags||[]).join(" ")].some(v=>String(v||"").toLowerCase().includes(term)));
  if(searchType==="category"&&term)list=list.filter(p=>productCategory(p).toLowerCase().includes(term));
  if(category&&category!=="All category")list=list.filter(p=>productCategory(p).toLowerCase()===category.toLowerCase());
  if(sellerFilter)list=list.filter(p=>String(p.seller_id)===sellerFilter);
  if(min!=="")list=list.filter(p=>productPrice(p)>=Number(min));
  if(max!=="")list=list.filter(p=>productPrice(p)<=Number(max));
  if(availability==="available")list=list.filter(p=>p.availability_status!=="out_of_stock"&&Number(p.stock??0)>0);
  if(availability==="unavailable")list=list.filter(p=>p.availability_status==="out_of_stock"||Number(p.stock??0)<=0);
  if(locationFilter)list=list.filter(p=>{const s=storeById[String(p.seller_id)];return[s?.city,s?.region,s?.country].some(v=>String(v||"").toLowerCase().includes(locationFilter.toLowerCase()))});
  if(Number(rating)>0)list=list.filter(p=>Number(p.rating||0)>=Number(rating));
  list.sort((a,b)=>sort==="oldest"?new Date(a.created_at||0)-new Date(b.created_at||0):sort==="price-low"?productPrice(a)-productPrice(b):sort==="price-high"?productPrice(b)-productPrice(a):sort==="rating"?Number(b.rating||0)-Number(a.rating||0):sort==="popular"?Number(b.sales_count||0)-Number(a.sales_count||0):new Date(b.created_at||0)-new Date(a.created_at||0));
  return list;
 },[products,search,searchType,category,min,max,availability,sort,locationFilter,rating,sellerFilter,storeById]);
 const storeResults=useMemo(()=>{const term=search.trim().toLowerCase();if(!term||!["all","seller","business"].includes(searchType))return[];return stores.filter(s=>[s.store_name,s.description,s.city,s.region,s.country].some(v=>String(v||"").toLowerCase().includes(term)))},[stores,search,searchType]);
 const categoryProducts=useMemo(()=>category&&category!=="All category"?products.filter(p=>productCategory(p).toLowerCase()===category.toLowerCase()):products,[products,category]);
 const featured=uniqueProducts(categoryProducts.filter(p=>p.is_featured||p.featured));
 const featuredIds=new Set(featured.map(p=>String(p.id)));
 const recommended=uniqueProducts(categoryProducts.filter(p=>p.is_recommended||p.recommended),featuredIds);
 const curatedIds=new Set([...featuredIds,...recommended.map(p=>String(p.id))]);
 const popular=uniqueProducts([...categoryProducts].sort((a,b)=>Number(b.sales_count||b.views_count||b.views||0)-Number(a.sales_count||a.views_count||a.views||0)),curatedIds);
 const shelfIds=new Set([...curatedIds,...popular.map(p=>String(p.id))]);
 const latest=uniqueProducts([...categoryProducts].sort((a,b)=>new Date(b.created_at||0)-new Date(a.created_at||0)),shelfIds);
 const suggestions=[...new Set([...products.slice(0,5).map(productCategory),...products.slice(0,5).map(productName)])].filter(Boolean).slice(0,8);
 function rememberSearch(){const value=search.trim();if(!value)return;const next=[value,...recent.filter(x=>x.toLowerCase()!==value.toLowerCase())].slice(0,8);Recent(next);localStorage.setItem("market-hub-recent-searches",JSON.stringify(next))}
 function searchSubmit(e){e.preventDefault();const value=search.trim();if(value){const next=[value,...recent.filter(x=>x.toLowerCase()!==value.toLowerCase())].slice(0,8);Recent(next);localStorage.setItem("market-hub-recent-searches",JSON.stringify(next))}SearchType("all");SellerFilter("");C("All category");navigate("/?search="+encodeURIComponent(value)+"&type=all#products")}
 function selectCategory(name){const selected=name||"All category";C(selected);S("");SearchType("category");SellerFilter("");navigate(selected==="All category"?"/?type=category#products":"/?category="+encodeURIComponent(selected)+"&type=category#products")}
 function selectStore(s){SellerFilter(String(s.seller_id));S("");SearchType("all");navigate("/?seller="+encodeURIComponent(s.seller_id)+"#products")}
 const gridProps={onQuickView:Q,onAdd:addToCart,loading:false,sellersById:storeById};
 const shelves=[["HANDPICKED FOR YOU","Featured products",featured],["A LITTLE INSPIRATION","Recommended for you",recommended],["LOVED BY SHOPPERS","Popular products",popular],["JUST ARRIVED","Latest products",latest]];
 return <main className="mh-shell">
  <StoreHeader onCart={()=>CO(true)} search={search} setSearch={S} onSearch={searchSubmit} products={products} onSelectCategory={selectCategory} selectedCategory={category}/>
  <HeroBanner search={search} setSearch={S} onSearch={searchSubmit}/>
  <PromotionalBanners/>
  <div className="mh-store-layout"><div className="mh-store-main">
  {shelves.map(([eyebrow,title,items])=>items.length>0&&<section id={title==="Featured products"?"featured":title==="Latest products"?"latest":undefined} className="mh-section mh-product-shelf" key={title}><div className="mh-section-heading"><div><span className="mh-eyebrow">{eyebrow}</span><h2>{title}</h2></div><a href="#products">Shop all <ArrowRight size={15}/></a></div><ProductGrid products={items} {...gridProps}/></section>)}
  <section className="mh-section" id="products">
   <div className="mh-section-heading"><div><span className="mh-eyebrow">THE MARKETPLACE</span><h2>{sellerFilter?"Products from selected business":category==="All category"?"Explore all products":category||"Explore all products"}</h2></div><span className="mh-results-count">{filtered.length} products{storeResults.length?" · "+storeResults.length+" businesses":""}</span></div>
   <ProductSearch value={search} onChange={S} onSubmit={searchSubmit} type={searchType} onTypeChange={SearchType} recent={recent} suggestions={suggestions} onPick={v=>S(v)}/>
   <ProductFilters products={products} category={category} setCategory={v=>{C(v);SellerFilter("")}} min={min} setMin={Min} max={max} setMax={Max} availability={availability} setAvailability={A} sort={sort} setSort={Sort} location={locationFilter} setLocation={LocationFilter} rating={rating} setRating={Rating}/>
   {recent.length>0&&<div className="mh-recent-searches"><b>Recent searches</b>{recent.map(v=><button key={v} onClick={()=>{S(v);SearchType("all");navigate("/?search="+encodeURIComponent(v)+"#products")}}>{v}</button>)}</div>}
   {searchType!=="product"&&storeResults.length>0&&<div className="mh-store-results"><div className="mh-section-heading"><div><span className="mh-eyebrow">SELLERS & BUSINESSES</span><h2>Matching businesses</h2></div></div><div className="mh-store-result-grid">{storeResults.map(s=><article className="mh-store-result" key={s.seller_id}>{s.logo_url?<img src={s.logo_url} alt=""/>:<span className="mh-store-result-icon"><Store size={21}/></span>}<div><strong>{s.store_name}</strong><p>{s.description||"Marketplace seller"}</p><small><MapPin size={12}/>{[s.city,s.region,s.country].filter(Boolean).join(", ")||"Location not provided"}</small></div><button onClick={()=>selectStore(s)}>View products</button></article>)}</div></div>}
   {error&&<p className="mh-data-error">Could not load listings: {error}. Check the products table and its public read policy in Supabase.</p>}
   {filtered.length>0?<ProductGrid products={filtered} onQuickView={Q} onAdd={addToCart} loading={loading} sellersById={storeById}/>:!loading&&<div className="mh-empty"><strong>No matching products found</strong><p>Try another keyword or adjust your filters.</p></div>}
  </section>
  </div></div>
  <section className="mh-seller-callout"><div><span className="mh-eyebrow">SELL ON MARKET HUB</span><h2>Your products deserve to be discovered.</h2><p>Open your seller account and reach customers through one shared marketplace.</p></div><a href="/auth/register/seller">Start selling <ArrowRight size={16}/></a></section>
  <footer className="mh-footer"><a className="mh-brand" href="/" aria-label="Market Hub home"><img className="mh-brand-logo" src="/market-hub-logo.svg" alt=""/><span className="mh-brand-name">market<b>hub</b></span></a><p>© {new Date().getFullYear()} Market Hub. Discover. Connect. Shop.</p><div><a href="/auth/login">Sign in</a><a href="/auth/register/customer">Create account</a></div></footer>
  <QuickView product={quick} onClose={()=>Q(null)} onAdd={addToCart}/><CartDrawer open={cartOpen} onClose={()=>CO(false)}/>
 </main>;
}