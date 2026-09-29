# FUTURE PHARMA

Mobile- and desktop-friendly pharmacy order, customer, product, recovery and ledger site. The GitHub repository hosts the website files; Supabase stores shared records and handles login so the same accounts/data work on your phone and PC.

## Setup once

1. Create a Supabase project at [supabase.com](https://supabase.com/).
2. In Supabase **SQL Editor**, run all of `supabase/schema.sql`. For an existing FUTURE PHARMA database, run `supabase/migration_eorder_book.sql`, then run `supabase/migration_punjab_geography.sql`. Both migrations add features without deleting current data. Keep a database backup before applying schema changes.
3. In **Authentication → Users**, add the first user with email `admin@futurepharma.local`, choose a password, and mark the email confirmed. In SQL Editor run:

   ```sql
   update public.profiles set role = 'admin' where username = 'admin';
   ```

   The trigger creates the profile when the auth user is created. This first username/password is your admin login.
4. Deploy the protected user-creation function from **Edge Functions → Deploy a new function → Via Editor**. Name it `create-user`. Open `supabase/functions/create-user/index.ts` from this folder, copy all its code, replace the starter code in the Supabase editor, and click **Deploy function**. Supabase provides the function's server-side secrets. Never copy its secret/service-role key into the website or GitHub. Supabase also supports CLI deployment if you prefer that workflow.
5. In Supabase **Project Settings → API Keys**, copy the Project URL and **publishable** key into `config.js`. Publishable keys are meant for browser use; database access is restricted by the SQL row-level security rules. Never put a secret/service-role key in `config.js`.
6. Upload the contents of this folder to your GitHub repository. In GitHub, turn on **Settings → Pages** and select the branch/folder containing `index.html`. Open the Pages link on your phone and PC and sign in with the same username/password.

## Included

- Username/password login, admin-only panel to add staff/admin accounts, and Pakistan time display.
- Dashboard greeting, outstanding total, today's recovery, open orders and customer count.
- Add/edit/delete customers and view each customer's order/recovery history and pending balance.
- Add/edit/delete products, Excel/CSV product upload, purchase and sale prices.
- Searchable product picker in orders; each order stores product, quantity, purchase price and sale price.
- Recovery entry, searchable recovery register, today's recovery, pending total and this month's recovery.
- Excel/CSV customer ledger import and customizable Excel download with Customer Ledger, Orders and Recoveries sheets.
- Additive E-Order Book upgrade: admin-managed sectors/areas, customer code/license expiry, product code/default discount/bonus, cascading order selection, product detail and selected-items workflow, server-generated daily invoice numbering, database-side totals, filtered reports, CSV exports, activity log, refresh/sync, and archive-delivered-orders control.
- Separate Punjab location hierarchy: the geography migration seeds 9 divisions, 41 districts from Punjab's 2025 LGCD demarcation notifications, and 157 tehsil entries. Admin can add, edit and delete division, district, tehsil and UC/town/locality records. Official locations stay separate from company sales sectors and sales areas; sales sectors and sales areas remain admin-managed too.
- `eorder-book.js` extends the existing pages while keeping the existing Dashboard, Recovery entry workflow, Ledger and Admin modules in place. “Send All” intentionally remains a destination-not-configured placeholder.

## Where your data is saved

Customer, product, order, recovery, sector, sales area and geographic location records are saved in your Supabase project's Postgres database. GitHub Pages serves the site code only. This is why updates made on one device are available after signing in on another. Download regular ledger/backup files from the Ledger page.

The Excel reader and Supabase JavaScript library load from public CDNs, so first load and Excel support require an internet connection.
