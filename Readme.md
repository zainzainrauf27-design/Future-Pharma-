# FUTURE PHARMA

Responsive order, customer, product, recovery and ledger website. GitHub Pages hosts the site files. Supabase stores shared records and handles sign-in, so the same accounts and data work on a phone and a computer.

## Existing project setup / update

1. Before changing the database, make a Supabase backup. In the existing database, run `supabase/migration_price_versions.sql` in Supabase → **SQL Editor**. It is additive: it retains order-line prices, creates selectable historical prices from prior orders, and safely updates the Staff Draft-saving function to store the exact selected version. Do not rerun `migration_staff_workflow.sql` if you already ran it; that older migration is not safe to repeat because it removes legacy generated Punjab geography tables. If you have not run the Staff workflow migration yet, run that once first, then run the price migration.
2. In GitHub, replace the website files with the files from this folder, including `index.html`, all `.js` and `.css` files, `service-worker.js`, and the `supabase` folder. Keep `config.js` configured with the project's URL and **publishable** API key. Never put a secret/service-role key in GitHub.
3. Wait for the GitHub Pages deployment to finish. On your phone, close the old site tab and open the deployed address again. On PC, refresh the page. Sign in online once on each device/account so the browser can save the login profile and offline data.
4. While online, open the Staff account at least once so customers, Areas, Sectors, products, price versions and order history are stored in that device's browser for offline work. Admin data is cached after Admin signs in. Add an Area, then its Sectors, and assign Customers before Staff starts orders.

## New database setup

For a brand-new Supabase project, run `supabase/schema.sql`, then `supabase/migration_eorder_book.sql`, then `supabase/migration_staff_workflow.sql`, then `supabase/migration_price_versions.sql`. Create the initial confirmed Auth user and promote its profile to admin using the setup steps in `supabase/schema.sql` / your existing README setup. Deploy `supabase/functions/create-user` if Admin should create staff accounts.

## Locations

There are only two location levels:

- **Area**: manually added by Admin.
- **Sector**: manually added under exactly one Area.

No Punjab, division, district, tehsil or union-council list is preloaded. An active Customer must be assigned to an active Area and one of its active Sectors.

## Staff order process

Staff can access only their own orders. Saving creates a **DRAFT**, which Staff can edit. **Confirm** changes it to **CONFIRMED** and locks it. **Send to Admin** changes it to **SUBMITTED**; only submitted/administrative orders enter the Admin order list. Database functions and row-level security enforce the ownership and state transitions as well as the interface.

## Offline use and syncing

- The first login for an account needs internet. After it has signed in, the browser keeps a local session/profile and a copy of that account's work data in IndexedDB.
- Staff can create and edit a local `LOCAL-ORD-######` Draft without internet. It is marked **Pending Sync** and appears in Drafts. When connection returns, the site automatically saves it as a server Draft using its stable request key, which prevents creating a second server order on retry.
- Syncing does **not** mark an order Confirmed or Submitted. Staff must be online to confirm it, then choose **Send to Admin** while online. A failed sync stays on the device as **Sync Failed** and can be retried.
- Offline records are stored in that browser and device; they are not shared with another phone/PC until they sync to Supabase. Do not clear browser site data while orders show Pending Sync. Offline data is not a substitute for the Supabase database backup.
- GitHub Pages can cache the app shell, and IndexedDB caches the datasets available at last online use. A brand-new browser/device must first connect and sign in. Availability of offline use depends on browser storage and previously cached data.

## Admin sections

Admin manages Customers, Products, Areas, Sectors, Orders, Recovery and user accounts. The Orders section includes date, staff, customer, Area, Sector, status and text filters. **Staff History** shows each staff member’s order totals/statuses, dates and attributed recoveries. Customer and Product records are deactivated instead of deleted so past Orders remain traceable. Orders can be archived for history.

## Product Excel columns

The product upload accepts `.xlsx`, `.xls` and `.csv`. Use headers such as `Product Name`, `Product Code`/`SKU`, `Company`, `Batch Number`, `Stock`, `Purchase Price`, `Sale Price`, `Default Discount`, and `Default Bonus`. Each row needs a product name. Check imported prices and quantities after upload.

Customer-ledger upload must have `Customer`/`Name`, `Area`, and `Sector` columns. Area and Sector text must exactly match the manually created names in Supabase. Existing customer names are updated; new names are inserted. Then balance/phone columns may use common headings such as `Balance`, `Outstanding`, `Phone`, or `Mobile`.

## Where records are saved

Customer, product, order, recovery, Area, Sector and account profile records live in the Supabase Postgres database. GitHub contains the website source only. Export the Excel ledger regularly and keep database backups. The Supabase JavaScript and Excel libraries load from public CDNs, so internet access is required.

## Important security note

`config.js` may contain only the Supabase Project URL and publishable key. Keep the `service_role`/secret key exclusively in Supabase server-side secrets. Enable/retain the row-level security and policies from the SQL schema and migrations. Apply the price-version migration before deploying the updated Staff ordering code; otherwise offline sync/price history may fail because the new table and order-item columns do not exist yet.
