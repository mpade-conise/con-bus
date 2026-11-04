import { ArrowRight, Search, ShoppingBag, Store } from "lucide-react";
import { Link } from "react-router-dom";

export default function Home() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="Market Hub home">
          <span className="brand-mark"><Store size={20} /></span>
          <span>market<span className="brand-accent">hub</span></span>
        </a>
        <nav className="nav-links" aria-label="Main navigation">
          <a href="#discover">Discover</a>
          <a href="#categories">Categories</a>
          <a href="#sell">Become a seller</a>
        </nav>
        <div className="header-actions">
          <button className="icon-button" aria-label="Search"><Search size={19} /></button>
          <button className="cart-button"><ShoppingBag size={17} /> Cart</button>
          <Link className="sign-in" to="/auth/login">Sign in</Link>
        </div>
      </header>

      <section className="hero" id="discover">
        <div className="hero-copy">
          <span className="eyebrow">YOUR MARKETPLACE, ALL IN ONE PLACE</span>
          <h1>Find what you need.<br /><span>Support local sellers.</span></h1>
          <p>Explore products and services from businesses in one simple marketplace.</p>
          <div className="hero-search">
            <Search size={19} />
            <input aria-label="Search products and sellers" placeholder="Search products, services and sellers..." />
            <button>Search <ArrowRight size={16} /></button>
          </div>
          <div className="hero-meta"><span>Discover local businesses</span><span>Shop with confidence</span></div>
        </div>
        <div className="hero-art" aria-hidden="true">
          <div className="art-card card-one"><span>✦</span><strong>Discover</strong><small>Something new</small></div>
          <div className="art-card card-two"><span>▦</span><strong>Shop</strong><small>Everyday essentials</small></div>
          <div className="art-orbit orbit-one"></div>
          <div className="art-orbit orbit-two"></div>
          <div className="art-center"><ShoppingBag size={54} strokeWidth={1.3} /></div>
        </div>
      </section>

      <section className="categories" id="categories">
        <div><span className="eyebrow">EXPLORE MARKET HUB</span><h2>Browse by category</h2></div>
        <p>Find products and services across the marketplace.</p>
        <div className="category-grid">
          {["Electronics", "Fashion", "Home & Living", "Food & Groceries", "Beauty & Care", "Services"].map((item, index) => (
            <a className="category-tile" href="#listings" key={item}><span>{["⌁", "◇", "⌂", "✳", "✦", "▤"][index]}</span><strong>{item}</strong><ArrowRight size={16} /></a>
          ))}
        </div>
      </section>

      <section className="listings" id="listings">
        <div><span className="eyebrow">THE MARKETPLACE</span><h2>Explore products</h2></div>
        <div className="empty-state"><ShoppingBag size={28} /><strong>Products will appear here</strong><p>Seller listings will be displayed on this shared marketplace homepage.</p></div>
      </section>

      <section className="seller-banner" id="sell">
        <div><span className="eyebrow">GROW YOUR BUSINESS</span><h2>Have something to sell?</h2><p>Create your seller space and reach customers through Market Hub.</p></div>
        <Link className="seller-cta" to="/auth/register/seller">Start selling <ArrowRight size={17} /></Link>
      </section>

      <footer><a className="brand" href="/"><span className="brand-mark"><Store size={17} /></span><span>market<span className="brand-accent">hub</span></span></a><span>© {new Date().getFullYear()} Market Hub</span></footer>
    </main>
  );
}
