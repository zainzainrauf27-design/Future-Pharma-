# FUTURE PHARMA

Responsive order, customer, product, recovery and ledger website. GitHub Pages hosts the site files. Supabase stores shared records and handles sign-in, so the same accounts and data work on a phone and a computer.

## Existing project setup / update

1. In GitHub, upload/replace the website files in this folder, keeping the `supabase` folder. GitHub Pages should point to the folder that contains `index.html`.
2. In Supabase → **SQL Editor**, run `supabase/migration_staff_workflow.sql` once. This is for the existing database after the earlier `migration_eorder_book.sql`. Do not run the old Punjab geography migration; the new migration removes its generated location hierarchy and keeps business Areas/Sectors manually managed. Take a database backup first. The migration keeps existing manual Area/Sector rows but does not guess their new parent relationship; review and assign each Sector to its correct Area afterward. Existing Customers may need their Area/Sector assignment checked again.
3. In GitHub, verify `config.js` has the project URL and **publishable** API key. Never place a secret/service-role key in GitHub.
4. Wait for GitHub Pages to finish deploying, then reload the site (on phone, close the old tab and reopen it). Existing Supabase accounts continue to sign in as before.
5. Sign in with an Admin account. Create an Area, then create one or more Sectors and assign each to its Area. Add Customers and Products before staff create orders.

## New database setup

For a brand-new Supabase project, run `supabase/schema.sql`, then `supabase/migration_eorder_book.sql`, then `supabase/migration_staff_workflow.sql`. Create the initial confirmed Auth user and promote its profile to admin using the setup steps in `supabase/schema.sql` / your existing README setup. Deploy `supabase/functions/create-user` if Admin should create staff accounts.

## Locations

There are only two location levels:

- **Area**: manually added by Admin.
- **Sector**: manually added under exactly one Area.

No Punjab, division, district, tehsil or union-council list is preloaded. An active Customer must be assigned to an active Area and one of its active Sectors.

## Staff order process

Staff can access only their own orders. Saving creates a **DRAFT**, which Staff can edit. **Confirm** changes it to **CONFIRMED** and locks it. **Send to Admin** changes it to **SUBMITTED**; only submitted/administrative orders enter the Admin order list. Database functions and row-level security enforce the ownership and state transitions as well as the interface.

## Admin sections

Admin manages Customers, Products, Areas, Sectors, Orders, Recovery and user accounts. The Orders section includes date, staff, customer, Area, Sector, status and text filters. **Staff History** shows each staff member’s order totals/statuses, dates and attributed recoveries. Customer and Product records are deactivated instead of deleted so past Orders remain traceable. Orders can be archived for history.

## Product Excel columns

The product upload accepts `.xlsx`, `.xls` and `.csv`. Use headers such as `Product Name`, `Product Code`/`SKU`, `Company`, `Batch Number`, `Stock`, `Purchase Price`, `Sale Price`, `Default Discount`, and `Default Bonus`. Each row needs a product name. Check imported prices and quantities after upload.

Customer-ledger upload must have `Customer`/`Name`, `Area`, and `Sector` columns. Area and Sector text must exactly match the manually created names in Supabase. Existing customer names are updated; new names are inserted. Then balance/phone columns may use common headings such as `Balance`, `Outstanding`, `Phone`, or `Mobile`.

## Where records are saved

Customer, product, order, recovery, Area, Sector and account profile records live in the Supabase Postgres database. GitHub contains the website source only. Export the Excel ledger regularly and keep database backups. The Supabase JavaScript and Excel libraries load from public CDNs, so internet access is required.

## Important security note

`config.js` may contain only the Supabase Project URL and publishable key. Keep the `service_role`/secret key exclusively in Supabase server-side secrets. Enable/retain the row-level security and policies from the SQL schema and migrations.
