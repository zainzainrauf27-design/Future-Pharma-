-- Run this once in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  role text not null default 'staff' check (role in ('admin','staff')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, username, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)), 'staff')
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(), name text not null, phone text default '', area text default '',
  opening_balance numeric(14,2) not null default 0, notes text default '', created_at timestamptz not null default now()
);
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(), name text not null, sku text default '', company text default '',
  purchase_price numeric(14,2) not null default 0, sale_price numeric(14,2) not null default 0,
  stock numeric(14,2) not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(), order_no text not null unique, customer_id uuid not null references public.customers(id),
  order_date date not null default current_date, status text not null default 'Pending' check (status in ('Pending','Dispatched','Delivered','Cancelled')),
  total numeric(14,2) not null default 0, notes text default '', created_at timestamptz not null default now()
);
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null, product_name text not null,
  qty numeric(14,2) not null default 1, purchase_price numeric(14,2) not null default 0,
  sale_price numeric(14,2) not null default 0, total numeric(14,2) not null default 0
);
create table if not exists public.recoveries (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id),
  amount numeric(14,2) not null check (amount > 0), received_at timestamptz not null default now(),
  method text default 'Cash', reference text default '', notes text default '', created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.recoveries enable row level security;

drop policy if exists "profile read self or admin" on public.profiles;
create policy "profile read self or admin" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "company users read profiles" on public.profiles;
create policy "company users read profiles" on public.profiles for select to authenticated using (true);
-- User creation and role changes are handled by the protected Edge Function, never by browser SQL.

do $$ declare t text; begin
  foreach t in array array['customers','products','orders','order_items','recoveries'] loop
    execute format('drop policy if exists "authenticated users manage %I" on public.%I',t,t);
    execute format('create policy "authenticated users manage %I" on public.%I for all to authenticated using (true) with check (true)',t,t);
  end loop;
end $$;
