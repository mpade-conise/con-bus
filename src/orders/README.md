# Order management integration

Run `orders.sql` in the Supabase SQL Editor **after**:
1. `src/authentication/authentication.sql`
2. `src/homepage/homepage.sql`
3. `src/sellers/sellers.sql`

## Connected flow
- Customer adds public products to the cart and submits delivery and payment preferences at `/checkout`.
- `place_marketplace_order` validates current product publication and stock, locks product rows, deducts stock, and creates one seller order per seller in a single database transaction.
- Seller dashboard reads only rows where `seller_id = auth.uid()`. New incoming orders and seller status changes are refreshed through Supabase Realtime.
- Customer `/orders` reads only rows where `customer_id = auth.uid()`, displays seller order references, item details, delivery/payment preferences and event history, and listens for seller updates.
- Customers can cancel pending/confirmed orders and request a return for delivered orders. Cancellation restores reserved stock. Order status events are written to `seller_order_events`.
- Sellers can confirm, process, prepare, ship, deliver or cancel orders according to the database-enforced transition rules. Cancelling restores stock. Seller dashboard provides printable order details.

## Status workflow
`pending → confirmed → processing → ready_for_delivery → shipped → delivered`

Cancellation is allowed before shipment according to the transition rules. `refunded` is reserved for a verified refund workflow; sellers cannot manually mark an order refunded.

## Current integration boundaries
- Delivery fee calculation is not configured. Checkout displays the delivery fee as to-be-agreed and does not include one in the total.
- Cash on delivery, Mobile Money and bank transfer are saved as payment preferences. This module does not initiate or verify an online payment; connect a payment provider and a trusted server-side webhook before treating a payment as paid.
- Order event history is an in-app tracking/notification timeline. Email, SMS and push notifications are not configured.
- Seller return requests are visible through the order's `return_status` and `return_reason`; a full seller return approval/refund workflow is a separate stage.

## Routes
- Customer checkout: `/checkout`
- Customer order history and tracking: `/orders`
- Seller order processing: Seller dashboard → Orders (`/seller`)

The SQL file is a migration and must be run once in the connected Supabase project. A GitHub commit does not execute SQL or deploy the Vercel website.
