# Homepage / Public Storefront

The `homepage.jsx` file is the homepage router imported by `src/App.jsx`. It owns the public storefront routes and shares the storefront cart/product context.

## Routes
- `/` — public marketplace homepage
- `/product/:id` — product details, seller information and customer reviews

## Supabase data
The storefront reads active listings from `public.products` using `select("*")`. To display the product cards fully, expose compatible fields such as:
- `id`, `name` or `title`, `description`
- `price`, optional `discount_price` / `original_price`
- `image_url` (or `image` / `images`), `category` / `category_name`
- `seller_id`, `created_at`, `stock` or `quantity`
- optional `is_active`, `is_featured`, `is_recommended`, `sales_count`, `views`, `rating`

Configure a public SELECT policy that exposes only listings intended for public display. The component filters inactive and draft listings when those fields are present. It does not create a product table because the seller catalogue module must own the canonical product schema.

Reviews are read from `public.reviews` with `product_id`, `rating`, `comment` and optional `customer_name` fields. Seller display details are read from `public.profiles`.

## Cart
The cart is a client-side convenience cart stored in the visitor's browser. Checkout is routed to sign-in; order creation, stock reservation and payment processing belong to the Orders and Payments modules and are not simulated here.
