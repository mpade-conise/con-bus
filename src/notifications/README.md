# Marketplace notifications

Run `src/notifications/notifications.sql` in Supabase SQL Editor **after** the existing authentication, homepage, sellers, orders, payments and messaging migrations. This is incremental; do not rerun earlier migrations.

## Included
- Customer and seller in-website notification inbox with unread count, history, read/unread filters and mark-all-read.
- Database-generated alerts for new orders, first-time customers per store, order confirmation/delivery/cancellation, successful/failed payments, new messages, low stock, back-in-stock products and active promotional banners.
- Realtime unread-count and inbox refresh.
- Customer product-availability subscriptions through `product_availability_subscriptions`.
- Per-user notification channel/category preferences table.

## Events and behaviour
- Low stock means five or fewer units, and alerts fire when stock crosses from above five to five or less.
- Back-in-stock alerts are sent to customers who subscribed to that product when stock changes from zero to a positive quantity.
- A new-customer alert is sent to a seller on that customer's first order with that seller.
- Promotional alerts are broadcast to active customer accounts when an active campaign is created or its content changes.

## Email and push delivery
The in-app system is implemented. Email and browser push require delivery infrastructure (an email provider, verified sender domain, Web Push VAPID keys, service worker and server-side delivery function). The preferences table reserves channel controls, but this commit does not claim email or push messages are being delivered. Configure those providers before enabling those channels.

## Access
Customers and sellers can open `/notifications`. The notification bell is available in the marketplace header and seller workspace. Row Level Security restricts notification reads and updates to the owning account; clients can update only `read_at`.
