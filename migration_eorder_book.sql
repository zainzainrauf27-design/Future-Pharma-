-- FUTURE PHARMA: additive E-Order Book upgrade for an EXISTING database.
-- Run once in Supabase SQL Editor. This preserves current rows and tables.

create extension if not exists pgcrypto;

create table if not exists public.sectors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (name)
);

create table if not exists public.areas (
  id uuid primary key default gen_random_uuid(),
  sector_id uuid not null references public.sectors(id) on delete restrict,
  name text not null,
  code text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (sector_id, name)
);
create unique index if not exists sectors_code_unique on public.sectors(code) where code <> '';
create unique index if not exists areas_code_unique on public.areas(code) where code <> '';

alter table public.customers add column if not exists customer_code text not null default '';
alter table public.customers add column if not exists sector_id uuid references public.sectors(id) on delete set null;
alter table public.customers add column if not exists area_id uuid references public.areas(id) on delete set null;
alter table public.customers add column if not exists license_expiry date;
create unique index if not exists customers_customer_code_unique on public.customers(customer_code) where customer_code <> '';

alter table public.products add column if not exists product_code text not null default '';
alter table public.products add column if not exists default_discount numeric(7,2) not null default 0;
alter table public.products add column if not exists default_bonus numeric(14,2) not null default 0;
update public.products set product_code = sku where product_code = '' and sku <> '';
create unique index if not exists products_product_code_unique on public.products(product_code) where product_code <> '';

alter table public.orders add column if not exists invoice_no text;
alter table public.orders add column if not exists sector_id uuid references public.sectors(id) on delete set null;
alter table public.orders add column if not exists area_id uuid references public.areas(id) on delete set null;
alter table public.orders add column if not exists remarks text not null default '';
alter table public.orders add column if not exists gross_total numeric(14,2) not null default 0;
alter table public.orders add column if not exists discount_total numeric(14,2) not null default 0;
alter table public.orders add column if not exists net_total numeric(14,2) not null default 0;
alter table public.orders add column if not exists item_count integer not null default 0;
alter table public.orders add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.orders add column if not exists archived_at timestamptz;
update public.orders set invoice_no = order_no where invoice_no is null;
update public.orders set gross_total = total, net_total = total where gross_total = 0 and total <> 0;
create unique index if not exists orders_invoice_no_unique on public.orders(invoice_no) where invoice_no is not null;
create index if not exists orders_order_date_idx on public.orders(order_date);
create index if not exists orders_sector_area_idx on public.orders(sector_id, area_id);
create index if not exists orders_customer_date_idx on public.orders(customer_id, order_date desc);

alter table public.order_items add column if not exists product_code text not null default '';
alter table public.order_items add column if not exists available_balance numeric(14,2) not null default 0;
alter table public.order_items add column if not exists discount_percent numeric(7,2) not null default 0;
alter table public.order_items add column if not exists discount_amount numeric(14,2) not null default 0;
alter table public.order_items add column if not exists bonus_qty numeric(14,2) not null default 0;
alter table public.order_items add column if not exists gross_amount numeric(14,2) not null default 0;
alter table public.order_items add column if not exists net_amount numeric(14,2) not null default 0;
update public.order_items set gross_amount = qty * sale_price, net_amount = total where gross_amount = 0;
create index if not exists order_items_order_id_idx on public.order_items(order_id);

-- Daily counter gives concurrent inserts unique YYMMDD0001-style invoice numbers.
create table if not exists public.invoice_counters (
  invoice_date date primary key,
  last_value integer not null check (last_value > 0)
);

create or replace function public.next_future_pharma_invoice(p_day date default current_date)
returns text language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into public.invoice_counters(invoice_date, last_value)
  values (p_day, coalesce((select max(substring(invoice_no from 7)::integer) from public.orders
                            where invoice_no like to_char(p_day, 'YYMMDD') || '%' and invoice_no ~ '^[0-9]{10}$'), 0) + 1)
  on conflict (invoice_date) do update set last_value = invoice_counters.last_value + 1
  returning last_value into n;
  return to_char(p_day, 'YYMMDD') || lpad(n::text, 4, '0');
end; $$;
revoke all on function public.next_future_pharma_invoice(date) from public, anon, authenticated;

create or replace function public.future_pharma_order_invoice()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.invoice_no, '') = '' then
    new.invoice_no := public.next_future_pharma_invoice(coalesce(new.order_date, current_date));
  end if;
  if coalesce(new.order_no, '') = '' or new.order_no like 'FP-%' then
    new.order_no := new.invoice_no;
  end if;
  return new;
end; $$;
drop trigger if exists future_pharma_order_invoice_trigger on public.orders;
create trigger future_pharma_order_invoice_trigger before insert on public.orders
for each row execute function public.future_pharma_order_invoice();

create or replace function public.future_pharma_calculate_item()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.qty <= 0 then raise exception 'Quantity must be greater than zero.'; end if;
  if new.sale_price < 0 or new.purchase_price < 0 then raise exception 'Price cannot be negative.'; end if;
  if new.discount_percent < 0 or new.discount_percent > 100 then raise exception 'Discount must be between 0 and 100 percent.'; end if;
  if new.bonus_qty < 0 then raise exception 'Bonus quantity cannot be negative.'; end if;
  new.gross_amount := round(new.qty * new.sale_price, 2);
  new.discount_amount := round(new.gross_amount * new.discount_percent / 100, 2);
  new.net_amount := new.gross_amount - new.discount_amount;
  new.total := new.net_amount;
  return new;
end; $$;
drop trigger if exists future_pharma_calculate_item_trigger on public.order_items;
create trigger future_pharma_calculate_item_trigger before insert or update on public.order_items
for each row execute function public.future_pharma_calculate_item();

create or replace function public.future_pharma_refresh_order_totals()
returns trigger language plpgsql security definer set search_path = public as $$
declare oid uuid;
begin
  oid := case when tg_op = 'DELETE' then old.order_id else new.order_id end;
  update public.orders o set
    gross_total = coalesce(x.gross, 0),
    discount_total = coalesce(x.discount, 0),
    net_total = coalesce(x.net, 0),
    total = coalesce(x.net, 0),
    item_count = coalesce(x.items, 0)
  from (select sum(gross_amount) gross, sum(discount_amount) discount, sum(net_amount) net, count(*)::integer items
        from public.order_items where order_id = oid) x
  where o.id = oid;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end; $$;
drop trigger if exists future_pharma_refresh_order_totals_trigger on public.order_items;
create trigger future_pharma_refresh_order_totals_trigger after insert or update or delete on public.order_items
for each row execute function public.future_pharma_refresh_order_totals();

-- Atomic, server-calculated order save. JSON item values are validated/recalculated by triggers above.
create or replace function public.create_future_pharma_order(
  p_customer_id uuid, p_sector_id uuid, p_area_id uuid, p_order_date date,
  p_status text, p_remarks text, p_items jsonb
) returns uuid language plpgsql security invoker set search_path = public as $$
declare oid uuid; item jsonb; c public.customers%rowtype; a public.areas%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  if p_status not in ('Pending','Dispatched','Delivered','Cancelled') then raise exception 'Invalid order status.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Add at least one product.'; end if;
  select * into c from public.customers where id = p_customer_id;
  if not found then raise exception 'Select a valid customer.'; end if;
  select * into a from public.areas where id = p_area_id and sector_id = p_sector_id and active;
  if not found then raise exception 'Select an active area from the selected sector.'; end if;
  insert into public.orders(order_no, customer_id, order_date, status, notes, remarks, sector_id, area_id, created_by)
  values ('', p_customer_id, coalesce(p_order_date, current_date), p_status, coalesce(p_remarks,''), coalesce(p_remarks,''), p_sector_id, p_area_id, auth.uid())
  returning id into oid;
  for item in select value from jsonb_array_elements(p_items) loop
    if coalesce((item->>'qty')::numeric,0) <= 0 then raise exception 'Quantity must be greater than zero.'; end if;
    insert into public.order_items(order_id, product_id, product_name, product_code, available_balance,
      qty, purchase_price, sale_price, discount_percent, bonus_qty)
    select oid, p.id, p.name, coalesce(nullif(p.product_code,''),p.sku), p.stock,
      (item->>'qty')::numeric, p.purchase_price,
      coalesce((item->>'price')::numeric,p.sale_price),
      coalesce((item->>'discount_percent')::numeric,p.default_discount),
      coalesce((item->>'bonus_qty')::numeric,p.default_bonus)
    from public.products p where p.id = (item->>'product_id')::uuid;
    if not found then raise exception 'An order product no longer exists.'; end if;
  end loop;
  return oid;
end; $$;
grant execute on function public.create_future_pharma_order(uuid,uuid,uuid,date,text,text,jsonb) to authenticated;

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists activities_created_at_idx on public.activities(created_at desc);
create index if not exists activities_user_id_idx on public.activities(user_id, created_at desc);

-- Audit changed column names only; never persist passwords, keys, or full row values.
create or replace function public.future_pharma_audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare oldj jsonb; newj jsonb; entity uuid; changed jsonb;
begin
  if tg_op = 'INSERT' then
    newj := to_jsonb(new); entity := (newj->>'id')::uuid;
    changed := coalesce((select jsonb_agg(key) from jsonb_object_keys(newj) as fields(key)), '[]'::jsonb);
  elsif tg_op = 'DELETE' then
    oldj := to_jsonb(old); entity := (oldj->>'id')::uuid;
    changed := '[]'::jsonb;
  else
    oldj := to_jsonb(old); newj := to_jsonb(new); entity := (newj->>'id')::uuid;
    select coalesce(jsonb_agg(n.key), '[]'::jsonb) into changed
    from jsonb_each(newj) n
    where n.key not in ('updated_at') and n.value is distinct from oldj->n.key;
  end if;
  insert into public.activities(user_id, action, entity_type, entity_id, details)
  values (auth.uid(), lower(tg_op), tg_table_name, entity, jsonb_build_object('changed_fields', changed));
  if tg_op = 'DELETE' then return old; end if;
  return new;
end; $$;

do $$ declare t text; begin
  foreach t in array array['customers','products','orders','order_items','recoveries','sectors','areas'] loop
    execute format('drop trigger if exists future_pharma_audit_trigger on public.%I', t);
    execute format('create trigger future_pharma_audit_trigger after insert or update or delete on public.%I for each row execute function public.future_pharma_audit_row()', t);
  end loop;
end $$;

alter table public.sectors enable row level security;
alter table public.areas enable row level security;
alter table public.activities enable row level security;
alter table public.invoice_counters enable row level security;

drop policy if exists "authenticated users manage sectors" on public.sectors;
drop policy if exists "authenticated users read sectors" on public.sectors;
drop policy if exists "admins manage sectors" on public.sectors;
create policy "authenticated users read sectors" on public.sectors for select to authenticated using (true);
create policy "admins manage sectors" on public.sectors for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "authenticated users manage areas" on public.areas;
drop policy if exists "authenticated users read areas" on public.areas;
drop policy if exists "admins manage areas" on public.areas;
create policy "authenticated users read areas" on public.areas for select to authenticated using (true);
create policy "admins manage areas" on public.areas for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "users read activities" on public.activities;
create policy "users read activities" on public.activities for select to authenticated using (true);
drop policy if exists "users create activities" on public.activities;
create policy "users create activities" on public.activities for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "admins manage activities" on public.activities;
create policy "admins manage activities" on public.activities for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- Counter table is only accessed by its SECURITY DEFINER invoice trigger/function.
