# Market Hub environment setup

1. Copy `.env.example` to a new file named `.env` in the project root (the same folder as `package.json`).
2. Replace the placeholders with the Supabase project URL and publishable/anon key from Supabase → Project Settings → API.
3. Restart the Vite development server after changing environment variables.

Required variables:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Never put a Supabase `service_role` key or any secret key in a `VITE_*` variable. Vite exposes `VITE_*` values to the browser. Keep the real `.env` file private; it is excluded by `.gitignore`.

For Vercel, add the same two variables under Project → Settings → Environment Variables, then redeploy. The `.env.example` file is only a template and contains no credentials.
