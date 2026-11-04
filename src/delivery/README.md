# Delivery and shipping management

Run `src/delivery/delivery.sql` in Supabase SQL Editor after the existing authentication, homepage, sellers, orders, and payments migrations. This is a new incremental migration; do not rerun the previous migrations. Coordinate this migration with deployment of the latest frontend: the new checkout calls `place_marketplace_order_with_delivery`, and the migration revokes direct access to the legacy order-placement RPC. Apply the migration and deploy the updated frontend as one release; checkout will not work correctly if only one side is updated.

## Features
- Customer address book with multiple saved addresses and a default address.
- Seller-configured home delivery and pickup availability.
- Seller-defined delivery zones with city/district matching, MWK delivery fees, and minimum/maximum delivery days.
- Checkout validates a zone for each seller in a multi-seller cart and adds each seller's fee to that seller order before payment begins.
- Pickup location and instructions saved with the order.
- Seller delivery personnel directory and order assignments.
- Tracking number, fulfilment status, estimated delivery date, delivery confirmation timestamp and event history.
- Customer can confirm receipt after dispatch; seller can also record confirmed delivery/collection.

## Routes
- Customer address book: `/customer/addresses`
- Seller delivery management: `/seller/delivery`
- Customer order tracking: `/orders`

## Notes
- Delivery zones and fees are seller-specific. Sellers must configure at least one active zone for home delivery. Pickup can be offered independently.
- Delivery personnel are seller-managed contacts/assignees; this does not create a driver login account or GPS tracking.
- Tracking numbers are seller-entered references. Carrier API tracking and live GPS are not included.
- Delivery estimates use seller-configured day ranges; they are estimates, not carrier guarantees.
