# Seller workspace

The seller dashboard is available at `/seller` and is mounted through `src/App.jsx`.

## Database setup

Run these scripts in Supabase SQL Editor in this order:

1. `src/authentication/authentication.sql`
2. `src/homepage/homepage.sql`
3. `src/sellers/sellers.sql`

The seller schema creates seller-owned categories, orders, customer messages and transaction records. It also creates the public `seller-assets` Storage bucket for store and product images. RLS policies scope seller data to the authenticated seller ID and active seller role.

## Seller capabilities

- Business overview and key metrics
- Store profile, logo, cover image, contact details and location
- Full product catalogue: multiple images, SKU, condition, specifications, variations, tags, price/discount, stock, availability, visibility, featured placement, preview, publish/unpublish, edit and delete
- Seller-specific product categories
- Customer order list and fulfilment status updates
- Customer message inbox and read status
- Revenue reports based on delivered orders
- Transaction history and customer statistics

## Access control

Only a logged-in user whose `profiles.role = 'seller'` and `profiles.is_active = true` can open `/seller`. The dashboard uses Supabase RLS; it does not rely on client-side route protection alone.

## Integration boundary

The dashboard reads seller orders, customer messages and payment transactions from `seller_orders`, `seller_messages` and `seller_transactions`. These records are populated by the checkout, customer messaging and payment workflows. Those workflows are separate integrations; this dashboard does not fabricate orders, messages, payouts or payment records. Transaction rows are read-only to sellers. Seller order updates are limited to fulfilment status and seller note.


## Product catalogue

The seller product form supports up to eight JPG, PNG or WebP images per listing (5 MB each), a main gallery image, seller-unique SKU, new/used/refurbished condition, specifications and selectable variation definitions, tags, inventory quantity, availability, public/private visibility, featured selection and a pre-publication preview. Only products with `status = 'published'`, `is_active = true` and `visibility = 'public'` are available to customer storefront queries. Private and draft listings remain available to their owner in the seller portal.

After deploying these changes, run the updated `src/homepage/homepage.sql` and then the updated `src/sellers/sellers.sql` in Supabase SQL Editor so the new catalogue columns, indexes, RLS policy and seller column grants are installed.
