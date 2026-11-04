# Homepage / Public Storefront

The `homepage.jsx` file is the public storefront router imported by `src/App.jsx`.

## Navigation
- `/` — public marketplace homepage.
- `/product/:id` — product details, seller/store information and customer reviews.
- Product cards and quick view link into the product details route; the details page links back to the marketplace.
- Authentication links use the routes registered by `src/authentication/auth.jsx`.
- Vercel's SPA rewrite supports direct visits and refreshes on these routes.

## Database setup
1. Run `src/authentication/authentication.sql` first. It creates `public.profiles`.
2. Run the complete `src/homepage/homepage.sql` in Supabase SQL Editor. It creates the homepage tables; it does not assume a products table already exists.
3. The SQL is re-runnable and configures Row Level Security.

## Tables created
- `product_categories` — public category navigation and administrator-managed category records.
- `seller_stores` — public-safe seller/store profile fields, separate from private `profiles`.
- `products` — seller listings, price/discount, stock, images, publication state, featured/recommended flags and popularity counters.
- `reviews` — customer ratings and comments; only approved reviews are public.
- `promotional_banners` — scheduled homepage promotions managed by administrators.

## Product publishing
A new product starts as `status = 'draft'`. A seller can manage only products where `seller_id = auth.uid()`. To show a listing publicly, set `is_active = true` and `status = 'published'`. Public RLS prevents visitors from reading drafts, pending, inactive or rejected products.

Required product fields include `seller_id`, `name`, and `price`. Use `category_id` to connect a category and also populate `category` / `category_name` for current storefront filtering. Images can use `image_url` and the `images` JSON array.

## Security
- Public visitors can read published products, active categories, public seller stores, current promotional banners and approved reviews.
- Sellers can create and manage only their own listings and store details.
- Customers can submit reviews for published products; reviews are pending until approved.
- Only administrator profiles can manage categories, promotional banners, and moderate reviews.
- Do not expose the entire `profiles` table publicly because it contains private phone numbers.

## Cart and checkout
The current cart is stored in the visitor's browser. Checkout routes to sign-in; order creation, stock reservation and payment processing belong to the separate Orders and Payments modules.
