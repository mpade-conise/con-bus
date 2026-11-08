# Online payments and seller finance

Run the following SQL files in the Supabase SQL Editor, in order:
1. `src/authentication/authentication.sql`
2. `src/homepage/homepage.sql`
3. `src/sellers/sellers.sql`
4. `src/orders/orders.sql`
5. `src/payments/payments.sql`
6. `src/payments/withdrawal-payout-hardening.sql`
7. `src/payments/automated-withdrawals.sql`

## Provider
This module uses PayChangu Standard Checkout. Its hosted checkout can present Airtel Money, TNM Mpamba and Visa/Mastercard when those channels are enabled for the merchant account. The customer selects a preferred channel in checkout and completes payment on PayChangu's hosted page. Card data never passes through this website.

Official documentation:
- https://developer.paychangu.com/docs/standard-checkout
- https://developer.paychangu.com/docs/webhooks
- https://developer.paychangu.com/docs/transaction-verification
- https://support.paychangu.com/hc/articles/24/supported-payment-methods

## Edge Functions
Deploy these Supabase Edge Functions from the repository:
- `supabase/functions/create-payment/index.ts`: authenticates the customer, creates a database payment intent, and requests a PayChangu hosted checkout session.
- `supabase/functions/payment-callback/index.ts`: receives the callback URL attached to each new marketplace checkout, verifies the transaction directly with PayChangu, checks the exact reference, amount and MWK currency, finalizes it once, and returns the customer to the marketplace.
- `supabase/functions/paychangu-webhook/index.ts`: optional signed webhook receiver for cases where this marketplace can be configured as the merchant account's global webhook.
- `supabase/functions/verify-payment/index.ts`: allows the signed-in customer return page to re-check a pending payment directly with PayChangu if the callback has not completed.
- `supabase/functions/create-withdrawal/index.ts`: administrator-only seller payout initiation. It claims each withdrawal once, submits to the correct PayChangu disbursement endpoint, and fails closed unless `PAYCHANGU_PAYOUTS_ENABLED=true`.
- `supabase/functions/verify-withdrawal/index.ts`: administrator-only payout verification using PayChangu's mobile-money or bank payout details endpoint. A withdrawal is marked paid only after its charge ID, amount, currency and successful provider status are verified.

Set Supabase Edge Function secrets (never put these in Vite variables or commit them):
- `PAYCHANGU_SECRET_KEY`: PayChangu API secret key.
- `PAYCHANGU_WEBHOOK_SECRET`: PayChangu Web Secret used to validate webhook signatures.
- `APP_URL`: deployed website origin, e.g. `https://your-marketplace-domain`.
- `PAYCHANGU_PAYOUTS_ENABLED`: set to `true` only after PayChangu confirms that API disbursements are activated for this merchant. Leave unset or `false` before activation.

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Keep the service role key server-side only.

Example CLI deployment:
```sh
supabase login
supabase link --project-ref pyzxfzexihwnyiknxaee
supabase secrets set PAYCHANGU_SECRET_KEY=... PAYCHANGU_WEBHOOK_SECRET=... APP_URL=https://your-marketplace-domain
supabase functions deploy create-payment
supabase functions deploy verify-payment
supabase functions deploy payment-callback
supabase functions deploy paychangu-webhook
supabase functions deploy create-withdrawal
supabase functions deploy verify-withdrawal
```

The marketplace sets its own `callback_url` on every payment request to `https://pyzxfzexihwnyiknxaee.supabase.co/functions/v1/payment-callback`. This is a per-transaction callback and does not require replacing the merchant account's existing global webhook URL. **Leave any webhook URL already used by another website unchanged.** The callback independently verifies each transaction against PayChangu before updating orders. The separate `paychangu-webhook` endpoint is retained for a future global-webhook setup; it has JWT verification disabled in `supabase/config.toml` and requires a valid HMAC signature.

## Connected flows
- Customer selects Airtel Money, TNM Mpamba, Visa/Mastercard or cash on delivery at `/checkout`.
- Online checkout creates a unique transaction reference and redirects to PayChangu.
- The return page and webhook both verify the transaction server-side. A browser redirect or client-side status is never treated as proof of payment.
- Verification requires exact transaction reference, MWK currency and exact expected amount before marking orders paid.
- Customer payment history is at `/transactions`; payment notifications appear on the same page.
- Customers can request refunds for paid cancelled or delivered orders. Administrators review each seller order separately, so one order in a multi-seller checkout can be refunded without incorrectly refunding the other sellers' orders. The actual refund is processed in PayChangu first, then reconciled in the admin dashboard.
- Stale payment sessions are expired after 30 minutes. A still-pending payment blocks a second attempt; late duplicate successful payments are flagged for a separate refund instead of crediting sellers twice.
- Seller earnings are calculated per seller order after the configured platform fee. Earnings become withdrawable only when the order is marked delivered.
- Sellers request withdrawals in Seller Dashboard → Transactions. Administrators use **Approve & Pay** at `/admin/payments`; the server claims each withdrawal once and submits it to PayChangu. Use **Check payout** to re-query an in-progress transfer. Customer collection functions remain separate.
- Administrator payment dashboard includes transactions, withdrawal requests, refunds, reconciliation records and configurable marketplace fee/minimum withdrawal.

## Financial controls and boundaries
- Platform fee defaults to **0%**. Configure the agreed commission in `marketplace_settings`; no commission rate is assumed. PayChangu's own processing fees are separate.
- Minimum withdrawal defaults to 0 MWK until the marketplace owner configures a policy.
- Bank transfers require a valid PayChangu `bank_uuid` in the saved destination. The current seller withdrawal form does not yet collect bank selection, so use Airtel Money or TNM Mpamba for automated payouts until that UI is added.
- Withdrawal requests are reserved against available seller earnings. Payout attempts are stored separately with a unique charge ID and terminal-state protection. Ambiguous network/provider responses remain `processing` for verification and are never automatically resubmitted. Only a verified provider success changes the withdrawal to `paid`; a verified failure changes it to `failed` and releases the reservation.
- Refunds are also reconciled manually: process the refund through PayChangu first, then an administrator confirms it in the dashboard. This avoids falsely marking money as refunded.
- The module does not store card numbers, CVV, or expiry details.
- Failed payment attempts remain visible and eligible orders can retry from customer order history.
- Payment notifications are in-app database notifications. Email/SMS/push delivery is not configured.

## Routes
- Customer checkout: `/checkout`
- Customer order history: `/orders`
- Customer transaction history and notifications: `/transactions`
- Payment return/status: `/payment-result?tx_ref=...`
- Seller earnings and withdrawals: Seller Dashboard → Transactions
- Administrator finance: `/admin/payments`

A GitHub commit does not run SQL, deploy Edge Functions, configure PayChangu credentials, or publish the Vercel frontend. Complete those setup steps before accepting live payments. Test with PayChangu test credentials first.
