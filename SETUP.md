# Faithly Fair — client setup

The shop is ready to preview with sample products. Complete these steps once to connect the live database, private admin area, payment proofs, and order email.

## 1. Create and connect Supabase

1. Create a project at Supabase and save the database password securely.
2. Open **SQL Editor → New query**, paste all of `supabase/migrations/001_faithly_fair.sql`, and run it once. This creates the tables, safe database functions, RLS rules, storage buckets, settings, hero, and starter products.
3. In **Project Settings → API**, copy the Project URL and public anon/publishable key.
4. Copy `.env.example` to `.env.local` and replace both placeholders. Never put the service-role key in this file or in the website.
5. Restart `npm run dev`. The storefront will now read products and content from Supabase.

## 2. Create the private admin account

1. In **Authentication → Users**, create the client’s email/password account. Use `Fairyfaithly@gmail.com` if that is the desired login.
2. Copy that user’s UUID.
3. In SQL Editor run the following, replacing the UUID:

```sql
insert into public.admin_users(user_id,email)
values ('PASTE-AUTH-USER-UUID','Fairyfaithly@gmail.com');
```

The admin logs in only at `/admin1199`. There is intentionally no public menu or footer link to this route. A Supabase dashboard login by itself does not grant website admin access; the allowlist row is intentionally required. Add another admin by creating another Auth user and inserting its UUID. Remove access by deleting its `admin_users` row.

## Customer order login

Run `supabase/migrations/003_customer_orders.sql` and then `supabase/migrations/004_email_order_login.sql` for an existing project. In **Authentication → Providers → Email**, enable email sign-in. Configure the Supabase email template to include `{{ .Token }}` (not only a magic-link URL), so customers receive a one-time code. Customers use that email code at `/orders`; after verification, every guest order matching their checkout email is securely linked to their account. Phone number, email, address, items, payment method, and order time are retained for every order.

## 3. Product images and payment proofs

The migration creates:

- `product-images` — public images; only allowlisted admins can modify files.
- `payment-proofs` — private, max 5 MB, JPG/PNG/WebP only. Customers can upload only inside a valid unexpired order-token folder. Only admins can read files.

For a product image, upload the file in **Storage → product-images**, copy its public URL, then insert it into `product_images` with the matching product ID. The product editor handles product data; direct image upload UI can be added later if the client needs it.

Payment proof is requested only for UPI. The QR contains the immutable server-calculated amount, `8920925990@fam`, `Faithly Fair`, INR, and the order number. A screenshot changes the order to `proof_submitted`; it does not prove bank settlement. Verify it manually in the admin area before changing payment to `verified` or `paid`.

## 4. eSewa ePay production setup

The customer's eSewa phone number/QR is **not** the merchant credential used by ePay. Automatic checkout requires an eSewa merchant **Product Code/Merchant ID** and **Secret Key** issued by eSewa. The secret key must stay in Supabase Edge Function secrets; never put it in `VITE_*` variables or the React app. eSewa's ePay flow requires a signed request and server-side transaction verification. citeturn0search1

Set the production credentials in Supabase:

```bash
npx supabase secrets set ESEWA_ENV=production ESEWA_PRODUCT_CODE=YOUR_MERCHANT_PRODUCT_CODE ESEWA_SECRET_KEY=YOUR_LIVE_ESEWA_SECRET
npx supabase functions deploy esewa-init --no-verify-jwt
npx supabase functions deploy esewa-verify --no-verify-jwt
```

For testing, use `ESEWA_ENV=uat` and the UAT credentials supplied by eSewa. Do not commit live credentials to GitHub. eSewa provides production merchant credentials after the merchant completes its required testing/onboarding. citeturn0search3

## 5. Automatic order email with Resend

1. Create a Resend account, verify a sender domain, and create an API key.
2. Install and sign in to the Supabase CLI, then link this folder to the project:

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
```

3. Create a long random webhook secret and set server-only secrets:

```bash
npx supabase secrets set RESEND_API_KEY=re_xxx ORDER_FROM_EMAIL="Faithly Fair <orders@yourdomain.com>" ORDER_TO_EMAIL=Fairyfaithly@gmail.com WEBHOOK_SECRET=YOUR_LONG_RANDOM_SECRET
npx supabase functions deploy notify-order --no-verify-jwt
```

4. In Supabase **Database → Webhooks**, add an `INSERT` webhook for `public.orders`. Point it to `https://YOUR_PROJECT_REF.supabase.co/functions/v1/notify-order` and add header `x-webhook-secret: YOUR_LONG_RANDOM_SECRET`.
5. Add a second webhook for `UPDATE` on `public.orders` if an email is also wanted when proof status changes. The function reads the current order securely and emails the fixed recipient.
6. Place a test order and check Resend logs and `Fairyfaithly@gmail.com`. An email failure never rolls back or loses the order.

## 6. WhatsApp and deployment

WhatsApp buttons use a free prefilled `wa.me` chat for `+91 89209 25880`; no Meta Cloud API or paid messaging setup is required. Change public business values in `site_settings` from the Supabase Table Editor.

Run the quality checks and deploy the generated app to Vercel, Netlify, or another Vite-compatible host:

```bash
npm run lint
npm run build
```

Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the host’s environment settings. Configure SPA fallback to `index.html` so `/checkout`, `/order/*`, and `/admin` work when opened directly.

## Security checklist

- Never expose the service-role key or Resend key in `VITE_*` variables.
- Keep RLS enabled on all tables and both storage buckets.
- Test a logged-out visitor cannot query `orders`, `order_items`, `payment_proofs`, or private storage.
- Review Supabase Auth logs, Edge Function logs, and Resend logs after launch.
- Back up the database before later migrations.
