# Online payments and seller finance

Run `payments.sql` in the Supabase SQL Editor **after** the existing migrations:
1. `src/authentication/authentication.sql`
2. `src/homepage/homepage.sql`
3. `src/sellers/sellers.sql`
4. `src/orders/orders.sql`
5. `src/payments/payments.sql`

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
- `supabase/functions/paychangu-webhook/index.ts`: validates the PayChangu HMAC-SHA256 Signature header, verifies the transaction directly with PayChangu, checks the exact reference, amount and MWK currency, and finalizes the payment once.
- `supabase/functions/verify-payment/index.ts`: allows the signed-in customer return page to re-check a pending payment directly with PayChangu if the webhook has not arrived.

Set Supabase Edge Function secrets (never put these in Vite variables or commit them):
- `PAYCHANGU_SECRET_KEY`: PayChangu API secret key.
- `PAYCHANGU_WEBHOOK_SECRET`: PayChangu Web Secret used to validate webhook signatures.
- `APP_URL`: deployed website origin, e.g. `https://your-marketplace-domain`.

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Keep the service role key server-side only.

Example CLI deployment:
```sh
supabase login
supabase link --project-ref qbqmhcoxmbpcjredofxs
supabase secrets set PAYCHANGU_SECRET_KEY=... PAYCHANGU_WEBHOOK_SECRET=... APP_URL=https://your-marketplace-domain
supabase functions deploy create-payment
supabase functions deploy verify-payment
supabase functions deploy paychangu-webhook
```

Configure the PayChangu dashboard webhook URL as:
`https://qbqmhcoxmbpcjredofxs.supabase.co/functions/v1/paychangu-webhook`
Enable payment events and use the Web Secret from the PayChangu dashboard. The webhook function has JWT verification disabled in `supabase/config.toml`, but it rejects requests without a valid HMAC signature.

## Connected flows
- Customer selects Airtel Money, TNM Mpamba, Visa/Mastercard or cash on delivery at `/checkout`.
- Online checkout creates a unique transaction reference and redirects to PayChangu.
- The return page and webhook both verify the transaction server-side. A browser redirect or client-side status is never treated as proof of payment.
- Verification requires exact transaction reference, MWK currency and exact expected amount before marking orders paid.
- Customer payment history is at `/transactions`; payment notifications appear on the same page.
- Customers can request refunds for paid cancelled or delivered orders. Administrators review each seller order separately, so one order in a multi-seller checkout can be refunded without incorrectly refunding the other sellers' orders. The actual refund is processed in PayChangu first, then reconciled in the admin dashboard.
- Stale payment sessions are expired after 30 minutes. A still-pending payment blocks a second attempt; late duplicate successful payments are flagged for a separate refund instead of crediting sellers twice.
- Seller earnings are calculated per seller order after the configured platform fee. Earnings become withdrawable only when the order is marked delivered.
- Sellers request withdrawals in Seller Dashboard → Transactions. Administrators review and record payout status at `/admin/payments`.
- Administrator payment dashboard includes transactions, withdrawal requests, refunds, reconciliation records and configurable marketplace fee/minimum withdrawal.

## Financial controls and boundaries
- Platform fee defaults to **0%**. Configure the agreed commission in `marketplace_settings`; no commission rate is assumed. PayChangu's own processing fees are separate.
- Minimum withdrawal defaults to 0 MWK until the marketplace owner configures a policy.
- Withdrawal requests are recorded and reserved against available seller earnings. The current admin workflow is manual: make/verify the payout in PayChangu or the bank, then record its status in the admin dashboard. Automated payout API execution is not enabled.
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
