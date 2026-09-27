# FUTURE PHARMA

Mobile- and desktop-friendly pharmacy order, customer, product, recovery and ledger site. The GitHub repository hosts the website files; Supabase stores shared records and handles login so the same accounts/data work on your phone and PC.

## Setup once

1. Create a Supabase project at [supabase.com](https://supabase.com/).
2. In Supabase **SQL Editor**, run all of `supabase/schema.sql`.
3. In **Authentication → Users**, add the first user with email `admin@futurepharma.local`, choose a password, and mark the email confirmed. In SQL Editor run:

   ```sql
   update public.profiles set role = 'admin' where username = 'admin';
   ```

   The trigger creates the profile when the auth user is created. This first username/password is your admin login.
4. Install the Supabase CLI, sign in, link this project, and deploy the protected user-creation function:

   ```sh
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase functions deploy create-user
   ```

   Supabase supplies the Edge Function its service role secret. Never copy that secret into the website or GitHub.
5. In Supabase **Project Settings → API**, copy the Project URL and anon/public key into `config.js`. The anon key is designed to be public; database access is restricted by the SQL row-level security rules.
6. Upload the contents of this folder to your GitHub repository. In GitHub, turn on **Settings → Pages** and select the branch/folder containing `index.html`. Open the Pages link on your phone and PC and sign in with the same username/password.

## Included

- Username/password login, admin-only panel to add staff/admin accounts, and Pakistan time display.
- Dashboard greeting, outstanding total, today's recovery, open orders and customer count.
- Add/edit/delete customers and view each customer's order/recovery history and pending balance.
- Add/edit/delete products, Excel/CSV product upload, purchase and sale prices.
- Searchable product picker in orders; each order stores product, quantity, purchase price and sale price.
- Recovery entry, searchable recovery register, today's recovery, pending total and this month's recovery.
- Excel/CSV customer ledger import and customizable Excel download with Customer Ledger, Orders and Recoveries sheets.

## Where your data is saved

Customer, product, order and recovery records are saved in your Supabase project's Postgres database. GitHub Pages serves the site code only. This is why updates made on one device are available after signing in on another. Download regular ledger/backup files from the Ledger page.

The Excel reader and Supabase JavaScript library load from public CDNs, so first load and Excel support require an internet connection.
