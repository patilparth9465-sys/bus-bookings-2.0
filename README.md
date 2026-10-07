# Bus booking system: setup guide

Files: `index.html` (customers), `admin.html` (you only), `supabase.sql` (database), `notify-function.ts` (SMS).

## How it works
1. Customer picks seats, enters name, phone and boarding point. Seats lock for 15 minutes for everyone.
2. Customer pays by scanning your UPI QR (amount is filled in) and enters the UTR, then taps "I have paid".
3. The seat map shows their seats as locked for them, and no one else can pick them. You get an SMS.
4. You check Paytm/bank, open `admin.html`, tap **Confirm**. Customer and you both get a confirmation SMS.
5. **Reject** releases the seats. If the customer never pays, the seats unlock after 15 minutes.

Payment is verified by you (amount + UTR in your Paytm app), not automatically. Fully automatic
verification needs a payment gateway such as Razorpay or Cashfree (fee, business KYC).

## Setup (about 1 hour, plus SMS approval time)
1. **Supabase**: create a free account and a new project at supabase.com. Pick the Mumbai region.
2. **Database**: SQL Editor, New query, paste all of `supabase.sql`, Run. Fare is `v_fare` (use 1 to test, 1299 live).
3. **Owner login**: Authentication, Users, Add user (your email + a strong password). Then Authentication,
   Sign In / Providers, turn **off** "Allow new users to sign up".
4. **Keys**: Project Settings, API. Copy the Project URL and the `anon` public key into the top of
   `index.html` (CONFIG) and `admin.html`. Never use the `service_role` key in these files.
5. **SMS (MSG91)**: create an account, complete **DLT registration** (company/PAN details, sender ID) and get
   4 templates approved: owner "new booking", customer "confirmed", owner "confirmed", customer "rejected".
   Use variables in the order described at the top of `notify-function.ts`. This approval takes days, so start now.
6. **Function**: Edge Functions, Create function named `notify`, paste `notify-function.ts`, Deploy. In its
   Secrets set `WEBHOOK_SECRET` (any long random text), `MSG91_AUTHKEY`, `OWNER_PHONE`, `TPL_OWNER_NEW`,
   `TPL_CUSTOMER_OK`, `TPL_OWNER_OK`, `TPL_CUSTOMER_NO`. Turn off "Verify JWT" for this function.
   Then Database, Webhooks, Create: table `bookings`, event **Update**, type HTTP Request, POST to the function URL,
   header `x-secret` = your WEBHOOK_SECRET.
7. **Host**: go to app.netlify.com/drop and drag the folder with `index.html` and `admin.html`. You get a free link.
   Share the main link with customers. Keep the `/admin.html` link private.
8. **Test**: book one seat with fare 1, pay Rs 1, confirm in admin, check both SMS arrive. Then set `v_fare` back
   to 1299 (re-run that function in SQL) and the `fare` value in `index.html`.

## Security notes
- Customers cannot read or edit any table. They can only call 4 checked functions. Seats can't double book (database rule).
- Only your logged-in account can confirm or reject.
- Never confirm from a screenshot. Match amount and UTR in your own app.
- Not included: spam limits on seat locking. If someone abuses it, add Cloudflare Turnstile or ask me to add a limit.
- Keep the page free of personal data you don't need. Phone numbers are visible only to you.
