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
- Product create, edit, delete, publish/unpublish, price, discount and inventory management
- Seller-specific product categories
- Customer order list and fulfilment status updates
- Customer message inbox and read status
- Revenue reports based on delivered orders
- Transaction history and customer statistics

## Access control

Only a logged-in user whose `profiles.role = 'seller'` and `profiles.is_active = true` can open `/seller`. The dashboard uses Supabase RLS; it does not rely on client-side route protection alone.

## Integration boundary

The dashboard reads seller orders, customer messages and payment transactions from `seller_orders`, `seller_messages` and `seller_transactions`. These records are populated by the checkout, customer messaging and payment workflows. Those workflows are separate integrations; this dashboard does not fabricate orders, messages, payouts or payment records. Transaction rows are read-only to sellers. Seller order updates are limited to fulfilment status and seller note.
