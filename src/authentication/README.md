# Authentication module

Routes: `/auth/login`, `/auth/register/customer`, `/auth/register/seller`, `/auth/verify-email`, `/auth/verify-phone`, `/auth/forgot-password`, `/auth/reset-password`, `/account/profile`, `/account/profile-picture`, `/account/change-password`, `/account/deactivate`, `/auth/logout`.

## Setup
1. Copy `.env.example` to `.env.local` and set the Supabase project URL and anon key.
2. Run `authentication.sql` in the Supabase SQL editor.
3. Enable email confirmations, configure SMS/phone auth, and allow the app redirect URLs in Supabase Auth.
4. Create/deploy the site with the same environment variables.

Never expose a Supabase service-role key in a Vite app. The administrator role must be assigned by trusted server-side code, not by a registration form. Deactivation currently marks the profile inactive and signs out; it does not delete the Supabase Auth user.
