# Wishlist and product reviews

Run only `src/homepage/wishlist_reviews.sql` in the Supabase SQL Editor for these incremental features. Do not rerun the existing migrations.

Prerequisites already present in this project: `profiles`, `products`, `reviews`, and `seller_orders` from the existing authentication, homepage, and orders migrations.

This migration:
- Persists each customer's wishlist in `customer_wishlist` with row-level security.
- Allows reviews only for products included in the customer's delivered orders.
- Adds up to four JPG, PNG, or WebP review photos (5 MB per image) using the `product-review-images` Storage bucket.
- Allows customers to edit and delete their own reviews.
- Keeps reviews pending moderation until an administrator approves them.
- Recalculates product average ratings and review counts from approved reviews.
- Allows customers to report another user's review through `review_reports`.
- Allows sellers to view reviews on their own products and publish seller responses.
- Restricts customer and seller updates to their permitted review fields.

## Where to test

- Customer: open `/customer/dashboard`, then Wishlist and Reviews & ratings.
- Product page: open a product to add/remove it from the wishlist and view approved reviews.
- Seller: open Seller Dashboard → Product reviews to respond to customer reviews.

A customer can submit a review after the order status is `delivered`. Reviews appear publicly after administrator approval. Administrators can approve/reject reviews and process reports at `/admin/reviews`.
