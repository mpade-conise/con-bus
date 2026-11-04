# Homepage / Public Storefront

The `homepage.jsx` file is the public storefront router imported by `src/App.jsx`. It owns the public storefront routes and shares the storefront cart/product context.

## Routes
- `/` — public marketplace homepage
- `/product/:id` — product details, seller information and customer reviews

Navigation between the marketplace and product details uses React Router links. The Vercel SPA rewrite keeps these routes working on direct visits and page refreshes.

## Supabase setup
1. Run `src/authentication/authentication.sql` first.
2. Run `src/homepage/homepage.sql` in the Supabase SQL Editor.
3. Run the seller catalogue SQL before the homepage SQL. The seller catalogue owns the canonical `public.products` table; this script deliberately does not create a competing products table.
4. Ensure the catalogue stores published products with `is_active = true` and `status = 'published'`.

The storefront reads `public.products` and expects compatible fields:
- Required: `id`, `name` or `title`, `description`, `price`, `created_at`
- Product display: `image_url` (or `image` / `images`), `category` / `category_name`, `seller_id`
- Availability: `stock` or `quantity`
- Storefront ranking: `is_featured`, `is_recommended`, `sales_count`, `views_count`
- Discounts: `discount_price` or `sale_price`

The SQL adds the storefront ranking, publication, discount and stock fields if they are missing. It also creates `public.reviews`, matching the existing product ID type, and applies row-level security:
- Visitors can read published, active products.
- Visitors can read approved reviews only.
- Signed-in customers can submit their own reviews for published products; new reviews require moderation.
- Administrators can moderate reviews.

Categories are derived from published products. Promotional banners are currently presentation content in the homepage; a separate promotions-management module can own database-driven campaigns.

## Seller/store information
Seller profile data is stored in `public.profiles`. Do not add a public SELECT policy to the entire profiles table: it also contains private fields such as phone numbers. Expose only approved public seller fields through a dedicated view/API before enabling public seller-profile reads.

## Cart and checkout
The cart is a client-side convenience cart stored in the visitor's browser. Checkout is routed to sign-in; order creation, stock reservation and payment processing belong to the Orders and Payments modules and are not simulated here.
