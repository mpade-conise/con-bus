# Security & privacy
Run security.sql after authentication, messaging and administrator migrations.

## Included
- Supabase Auth manages password hashing, email verification, token refresh and session persistence. Passwords are never stored in the marketplace profile table.
- A database trigger prevents users from changing their own role, active/suspended state, deactivation timestamp or profile identity fields.
- Account security events record successful sign-ins, password changes, sign-outs, verification requests and global session revocations. Users can view their own activity.
- Security Center at /account/security supports email verification resend, password changes, recent activity export and global sign-out.
- Existing row-level security policies protect orders, payments, messaging, addresses and account data. Existing messaging block/report workflows remain available.
- Account reports and administrator moderation are supplied by the administrator and messaging migrations.

## Required Supabase project configuration
1. Enable email confirmations and configure verified redirect URLs in Authentication > URL Configuration.
2. Set Auth password policy, email/SMS OTP expiry and rate limits in Authentication settings. Apply CAPTCHA / Turnstile to public sign-up and sign-in where supported.
3. Keep leaked-password protection enabled where available. Supabase Auth hashes passwords; do not implement client-side password hashing.
4. Require MFA for administrator accounts. Restrict administrator account creation to trusted database/server-side operations.
5. Configure database backups and point-in-time recovery according to the Supabase plan. Periodically test restoration; this SQL migration does not create an independent backup.
6. Configure alerts and review Auth, API, database and Edge Function logs. IP address and failed-login auditing should be handled by trusted server-side infrastructure; this browser activity log does not capture IP addresses or failed password attempts.
7. Configure payment provider fraud controls and verify every payment server-side. This migration does not implement a risk-scoring engine or replace PayChangu verification.

Never expose a Supabase service-role key in browser code. VITE_ variables are public. Do not store card numbers, CVV or payment passwords in marketplace tables.
