-- FUTURE PHARMA: Staff draft/confirm/submit workflow and Area -> Sector hierarchy.
-- Run after migration_eorder_book.sql. Supersedes and removes the obsolete Punjab geography migration data if it was previously applied.
-- Existing customer/order/product/recovery records are preserved.

create extension if not exists pgcrypto;

-- Retire the previous Punjab-wide hierarchy and generated GEO sales entries.
-- Copy historical location text before their generated Area/Sector rows are removed.
alter table public.orders add column if not exists customer_name_snapshot text;
alter table public.orders add column if not exists customer_code_snapshot text;
alter table public.orders add column if not exists customer_area_snapshot text;
alter table public.orders add column if not exists customer_sector_snapshot text;
update public.orders o set customer_name_snapshot=c.name,customer_code_snapshot=c.customer_code,
  customer_area_snapshot=coalesce(a.name,c.area),customer_sector_snapshot=s.name
from public.customers c left join public.areas a on a.id=c.area_id left join public.sectors s on s.id=c.sector_id
where o.customer_id=c.id and o.customer_name_snapshot is null;
-- GEO-* rows came from the obsolete auto-seed, not the business's manual areas.
delete from public.areas where code like 'GEO-%';
delete from public.sectors where code like 'GEO-%';
do $$ declare c record; begin
  for c in select column_name from information_schema.columns where table_schema='public' and table_name='customers'
    and column_name in ('division_id','district_id','tehsil_id','locality_id') loop
    execute format('alter table public.customers drop column %I',c.column_name);
  end loop;
end $$;
drop function if exists public.future_pharma_sync_geo_sales_records();
drop table if exists public.punjab_localities cascade;
drop table if exists public.punjab_tehsils cascade;
drop table if exists public.punjab_districts cascade;
drop table if exists public.punjab_divisions cascade;

-- Move the relationship to the required direction: an Area can contain many Sectors.
alter table public.areas alter column sector_id drop not null;
alter table public.sectors add column if not exists area_id uuid references public.areas(id) on delete set null;
alter table public.sectors add column if not exists active boolean not null default true;
alter table public.areas add column if not exists active boolean not null default true;
alter table public.customers add column if not exists active boolean not null default true;
alter table public.products add column if not exists active boolean not null default true;
alter table public.products add column if not exists batch_no text not null default '';
alter table public.order_items add column if not exists product_company text not null default '';
alter table public.order_items add column if not exists batch_no text not null default '';
alter table public.sectors add column if not exists updated_at timestamptz not null default now();
alter table public.areas add column if not exists updated_at timestamptz not null default now();
alter table public.customers add column if not exists updated_at timestamptz not null default now();
alter table public.products add column if not exists updated_at timestamptz not null default now();
create index if not exists sectors_area_idx on public.sectors(area_id);
create index if not exists customers_area_sector_idx on public.customers(area_id,sector_id);

-- Do not guess the reversed legacy location relationship. Existing Areas and Sectors
-- remain available, and Admin assigns each Sector to the correct Area manually.

-- Make customer codes permanent and unique. Area prefix + atomic counter (e.g. RA0001).
create table if not exists public.customer_code_counters(prefix text primary key,last_value integer not null check(last_value>0));
update public.customers set customer_code=nullif(btrim(customer_code),'');
with ranked as (select id,row_number() over(partition by customer_code order by id) as n from public.customers where customer_code is not null and customer_code<>'') update public.customers c set customer_code=null from ranked r where r.id=c.id and r.n>1;
with bases as (
  select c.id,coalesce(a.name,'') area_name,
    case when upper(left(regexp_replace(coalesce(a.name,''),'[^A-Za-z]','','g'),2))='' then 'XX'
         when length(upper(left(regexp_replace(coalesce(a.name,''),'[^A-Za-z]','','g'),2)))=1 then rpad(upper(left(regexp_replace(a.name,'[^A-Za-z]','','g'),2)),2,'X')
         else upper(left(regexp_replace(a.name,'[^A-Za-z]','','g'),2)) end prefix
  from public.customers c left join public.areas a on a.id=c.area_id where c.customer_code is null or c.customer_code=''
), numbered as (
  select b.id,b.prefix,
    coalesce((select max(case when c.customer_code ~ ('^'||b.prefix||'[0-9]+$') then substring(c.customer_code from 3)::integer end) from public.customers c),0)
      + row_number() over(partition by b.prefix order by b.id) n
  from bases b
)
update public.customers c set customer_code=n.prefix||lpad(n.n::text,4,'0') from numbered n where c.id=n.id;
insert into public.customer_code_counters(prefix,last_value)
select left(customer_code,2),max(substring(customer_code from 3)::integer) from public.customers where customer_code ~ '^[A-Z]{2}[0-9]+$'
group by left(customer_code,2) on conflict(prefix) do update set last_value=greatest(customer_code_counters.last_value,excluded.last_value);
create unique index if not exists customers_customer_code_unique on public.customers(customer_code) where customer_code is not null and customer_code<>'';
create or replace function public.future_pharma_customer_code()
returns trigger language plpgsql security definer set search_path=public as $$
declare n integer; area_name text; prefix text;
begin
  if tg_op='UPDATE' then new.customer_code:=old.customer_code; return new; end if;
  if nullif(btrim(new.customer_code),'') is not null then raise exception 'Customer code is generated automatically.'; end if;
  select name into area_name from public.areas where id=new.area_id;
  prefix:=upper(left(regexp_replace(coalesce(area_name,''),'[^A-Za-z]','','g'),2));
  if length(prefix)<2 then prefix:=rpad(coalesce(prefix,'CU'),2,'X'); end if;
  insert into public.customer_code_counters(prefix,last_value)
  values(prefix,coalesce((select max(case when customer_code ~ ('^'||prefix||'[0-9]+$') then substring(customer_code from 3)::integer end) from public.customers),0)+1)
  on conflict(prefix) do update set last_value=customer_code_counters.last_value+1 returning last_value into n;
  new.customer_code:=prefix||lpad(n::text,4,'0');
  return new;
end; $$;
drop trigger if exists future_pharma_customer_code_trigger on public.customers;
create trigger future_pharma_customer_code_trigger before insert or update of customer_code on public.customers
for each row execute function public.future_pharma_customer_code();

create or replace function public.future_pharma_validate_customer_assignment()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.active and (new.area_id is null or new.sector_id is null) then
    raise exception 'Choose an Area and a Sector for every active customer.';
  end if;
  if new.active and not exists(select 1 from public.areas a join public.sectors s on s.area_id=a.id where a.id=new.area_id and a.active and s.id=new.sector_id and s.active) then
    raise exception 'Choose an active Sector that belongs to an active Area.';
  end if;
  return new;
end; $$;
drop trigger if exists future_pharma_validate_customer_assignment_trigger on public.customers;
create trigger future_pharma_validate_customer_assignment_trigger before insert or update of area_id,sector_id,active on public.customers
for each row execute function public.future_pharma_validate_customer_assignment();

alter table public.orders add column if not exists request_key uuid;
alter table public.orders add column if not exists updated_at timestamptz not null default now();
alter table public.orders add column if not exists confirmed_at timestamptz;
alter table public.orders add column if not exists submitted_at timestamptz;
alter table public.orders add column if not exists processed_at timestamptz;
alter table public.orders add column if not exists completed_at timestamptz;
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists customer_name_snapshot text;
alter table public.orders add column if not exists customer_code_snapshot text;
alter table public.orders add column if not exists customer_area_snapshot text;
alter table public.orders add column if not exists customer_sector_snapshot text;
create unique index if not exists orders_request_key_unique on public.orders(request_key) where request_key is not null;
update public.orders set customer_name_snapshot=c.name,customer_code_snapshot=c.customer_code,
  customer_area_snapshot=a.name,customer_sector_snapshot=s.name
from public.customers c left join public.areas a on a.id=c.area_id left join public.sectors s on s.id=c.sector_id
where public.orders.customer_id=c.id and public.orders.customer_name_snapshot is null;

do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.orders'::regclass and contype='c'
    and pg_get_constraintdef(oid) ilike '%status%' loop
    execute format('alter table public.orders drop constraint %I',c.conname);
  end loop;
end $$;
alter table public.orders add constraint orders_status_workflow_check check(status in
 ('Pending','Dispatched','Delivered','Cancelled','DRAFT','CONFIRMED','SUBMITTED','PROCESSING','APPROVED','REJECTED','COMPLETED'));
create index if not exists orders_created_by_status_idx on public.orders(created_by,status,order_date desc);

create or replace function public.future_pharma_order_timestamps()
returns trigger language plpgsql set search_path=public as $$
begin
  new.updated_at:=now();
  if new.status is distinct from old.status then
    if new.status='PROCESSING' then new.processed_at:=coalesce(new.processed_at,now()); end if;
    if new.status='COMPLETED' then new.completed_at:=coalesce(new.completed_at,now()); end if;
    if new.status in ('Cancelled','CANCELLED') then new.cancelled_at:=coalesce(new.cancelled_at,now()); end if;
  end if;
  return new;
end; $$;
drop trigger if exists future_pharma_order_timestamps_trigger on public.orders;
create trigger future_pharma_order_timestamps_trigger before update on public.orders
for each row execute function public.future_pharma_order_timestamps();

-- Atomically create or replace only the signed-in user's own draft and its items.
create or replace function public.save_future_pharma_draft(
  p_order_id uuid,p_request_key uuid,p_customer_id uuid,p_area_id uuid,p_sector_id uuid,
  p_order_date date,p_remarks text,p_items jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare oid uuid; item jsonb; cust public.customers%rowtype; a public.areas%rowtype; s public.sectors%rowtype; prod public.products%rowtype; q numeric; price numeric; disc numeric; bonus numeric;
begin
  if auth.uid() is null or public.is_admin() then raise exception 'Staff sign-in required.'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one product.'; end if;
  select * into cust from public.customers where id=p_customer_id and active;
  if not found then raise exception 'Select an active customer.'; end if;
  select * into a from public.areas where id=p_area_id and active;
  if not found then raise exception 'Select an active area.'; end if;
  select * into s from public.sectors where id=p_sector_id and active and area_id=p_area_id;
  if not found then raise exception 'Select a sector that belongs to the selected area.'; end if;
  if cust.area_id is distinct from p_area_id or cust.sector_id is distinct from p_sector_id then raise exception 'Selected customer does not belong to this Area and Sector.'; end if;
  if p_order_id is null then
    if p_request_key is null then raise exception 'Order request key missing; reload and try again.'; end if;
    insert into public.orders(order_no,customer_id,order_date,status,total,notes,remarks,sector_id,area_id,created_by,request_key,
      customer_name_snapshot,customer_code_snapshot,customer_area_snapshot,customer_sector_snapshot)
    values ('',p_customer_id,coalesce(p_order_date,current_date),'DRAFT',0,coalesce(p_remarks,''),coalesce(p_remarks,''),p_sector_id,p_area_id,auth.uid(),p_request_key,
      cust.name,cust.customer_code,a.name,s.name)
    on conflict(request_key) where request_key is not null do update set customer_id=excluded.customer_id,order_date=excluded.order_date,
      notes=excluded.notes,remarks=excluded.remarks,sector_id=excluded.sector_id,area_id=excluded.area_id,
      customer_name_snapshot=excluded.customer_name_snapshot,customer_code_snapshot=excluded.customer_code_snapshot,
      customer_area_snapshot=excluded.customer_area_snapshot,customer_sector_snapshot=excluded.customer_sector_snapshot,updated_at=now()
      where orders.created_by=auth.uid() and orders.status='DRAFT'
    returning id into oid;
    if oid is null then raise exception 'This draft is no longer editable.'; end if;
  else
    select id into oid from public.orders where id=p_order_id and created_by=auth.uid() and status='DRAFT' for update;
    if not found then raise exception 'Only your own Draft orders can be edited.'; end if;
    update public.orders set customer_id=p_customer_id,order_date=coalesce(p_order_date,current_date),notes=coalesce(p_remarks,''),remarks=coalesce(p_remarks,''),
      sector_id=p_sector_id,area_id=p_area_id,customer_name_snapshot=cust.name,customer_code_snapshot=cust.customer_code,
      customer_area_snapshot=a.name,customer_sector_snapshot=s.name,updated_at=now() where id=oid;
    delete from public.order_items where order_id=oid;
  end if;
  for item in select value from jsonb_array_elements(p_items) loop
    q:=coalesce((item->>'qty')::numeric,0); price:=coalesce((item->>'price')::numeric,-1);
    disc:=coalesce((item->>'discount_percent')::numeric,0); bonus:=coalesce((item->>'bonus_qty')::numeric,0);
    if q<=0 then raise exception 'Every product quantity must be greater than zero.'; end if;
    if price<0 then raise exception 'Product price cannot be negative.'; end if;
    if disc<0 or disc>100 then raise exception 'Discount must be between 0 and 100 percent.'; end if;
    if bonus<0 then raise exception 'Bonus quantity cannot be negative.'; end if;
    select * into prod from public.products where id=(item->>'product_id')::uuid and active;
    if not found then raise exception 'A selected product is missing or inactive.'; end if;
    insert into public.order_items(order_id,product_id,product_name,product_code,product_company,batch_no,available_balance,qty,purchase_price,sale_price,discount_percent,bonus_qty)
    values(oid,prod.id,prod.name,coalesce(nullif(prod.product_code,''),prod.sku),prod.company,prod.batch_no,prod.stock,q,prod.purchase_price,price,disc,bonus);
  end loop;
  return oid;
end; $$;
revoke all on function public.save_future_pharma_draft(uuid,uuid,uuid,uuid,uuid,date,text,jsonb) from public,anon;
grant execute on function public.save_future_pharma_draft(uuid,uuid,uuid,uuid,uuid,date,text,jsonb) to authenticated;

create or replace function public.confirm_future_pharma_order(p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare n integer; oid uuid;
begin
  if auth.uid() is null or public.is_admin() then raise exception 'Staff sign-in required.'; end if;
  select customer_id into oid from public.orders where id=p_order_id and created_by=auth.uid() and status='DRAFT' for update;
  if not found then raise exception 'Only your own Draft order can be confirmed.'; end if;
  if not exists(select 1 from public.customers c join public.areas a on a.id=c.area_id and a.active join public.sectors s on s.id=c.sector_id and s.active and s.area_id=a.id where c.id=oid and c.active) then raise exception 'The selected Customer, Area or Sector is no longer active or correctly assigned.'; end if;
  select count(*) into n from public.order_items where order_id=p_order_id and qty>0 and sale_price>=0 and discount_percent between 0 and 100;
  if n=0 then raise exception 'Add at least one valid product before confirming.'; end if;
  update public.orders set status='CONFIRMED',confirmed_at=now(),updated_at=now() where id=p_order_id;
end; $$;
revoke all on function public.confirm_future_pharma_order(uuid) from public,anon;
grant execute on function public.confirm_future_pharma_order(uuid) to authenticated;

create or replace function public.submit_future_pharma_order(p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or public.is_admin() then raise exception 'Staff sign-in required.'; end if;
  update public.orders set status='SUBMITTED',submitted_at=now(),updated_at=now()
  where id=p_order_id and created_by=auth.uid() and status='CONFIRMED';
  if not found then raise exception 'Only your own confirmed order can be submitted.'; end if;
end; $$;
revoke all on function public.submit_future_pharma_order(uuid) from public,anon;
grant execute on function public.submit_future_pharma_order(uuid) to authenticated;

-- Prevent direct client use of the legacy all-at-once order RPC by Staff.
create or replace function public.create_future_pharma_order(
  p_customer_id uuid,p_sector_id uuid,p_area_id uuid,p_order_date date,p_status text,p_remarks text,p_items jsonb
) returns uuid language plpgsql security invoker set search_path=public as $$
declare oid uuid; item jsonb;
begin
  if not public.is_admin() then raise exception 'Staff orders must be saved as Draft, then confirmed and submitted.'; end if;
  if p_status not in ('Pending','Dispatched','Delivered','Cancelled') then raise exception 'Invalid admin order status.'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one product.'; end if;
  if not exists(select 1 from public.customers where id=p_customer_id and active) then raise exception 'Select an active customer.'; end if;
  insert into public.orders(order_no,customer_id,order_date,status,notes,remarks,sector_id,area_id,created_by,
    customer_name_snapshot,customer_code_snapshot,customer_area_snapshot,customer_sector_snapshot)
  select '',c.id,coalesce(p_order_date,current_date),p_status,coalesce(p_remarks,''),coalesce(p_remarks,''),p_sector_id,p_area_id,auth.uid(),
    c.name,c.customer_code,a.name,s.name
  from public.customers c join public.areas a on a.id=p_area_id join public.sectors s on s.id=p_sector_id and s.area_id=a.id
  where c.id=p_customer_id and c.area_id=p_area_id and c.sector_id=p_sector_id returning id into oid;
  if oid is null then raise exception 'Customer, Area and Sector relationship is invalid.'; end if;
  for item in select value from jsonb_array_elements(p_items) loop
    insert into public.order_items(order_id,product_id,product_name,product_code,product_company,batch_no,available_balance,qty,purchase_price,sale_price,discount_percent,bonus_qty)
    select oid,p.id,p.name,coalesce(nullif(p.product_code,''),p.sku),p.company,p.batch_no,p.stock,(item->>'qty')::numeric,p.purchase_price,
      coalesce((item->>'price')::numeric,p.sale_price),coalesce((item->>'discount_percent')::numeric,p.default_discount),
      coalesce((item->>'bonus_qty')::numeric,p.default_bonus)
    from public.products p where p.id=(item->>'product_id')::uuid and p.active;
    if not found then raise exception 'An order product is missing or inactive.'; end if;
  end loop;
  return oid;
end; $$;
revoke all on function public.create_future_pharma_order(uuid,uuid,uuid,date,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_future_pharma_order(uuid,uuid,uuid,date,text,text,jsonb) to authenticated;

-- Add Staff ownership to recoveries without rewriting old recovery history.
alter table public.recoveries add column if not exists collected_by uuid references auth.users(id) on delete set null;
alter table public.recoveries add column if not exists order_id uuid references public.orders(id) on delete set null;

-- Backend permissions: staff read master data and create own workflow orders only through RPC.
do $$ declare t text; p record; begin
  foreach t in array array['profiles','customers','products','orders','order_items','recoveries','sectors','areas','activities','customer_code_counters'] loop
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I',p.policyname,t);
    end loop;
  end loop;
end $$;

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.recoveries enable row level security;
alter table public.sectors enable row level security;
alter table public.areas enable row level security;
alter table public.activities enable row level security;
alter table public.customer_code_counters enable row level security;

create policy "profile read self or admin" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy "staff read active customers admin read all" on public.customers for select to authenticated using(active or public.is_admin());
create policy "admin manage customers" on public.customers for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "staff read active products admin read all" on public.products for select to authenticated using(active or public.is_admin());
create policy "admin manage products" on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "staff read active sectors admin read all" on public.sectors for select to authenticated using(active or public.is_admin());
create policy "admin manage sectors" on public.sectors for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "staff read active areas admin read all" on public.areas for select to authenticated using(active or public.is_admin());
create policy "admin manage areas" on public.areas for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "orders visible by owner or admin" on public.orders for select to authenticated using(created_by=auth.uid() or public.is_admin());
create policy "admin insert orders" on public.orders for insert to authenticated with check(public.is_admin());
create policy "admin update orders" on public.orders for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin delete orders" on public.orders for delete to authenticated using(public.is_admin());
create policy "order items visible with parent order" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id));
create policy "admin insert order items" on public.order_items for insert to authenticated with check(public.is_admin());
create policy "admin update order items" on public.order_items for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin delete order items" on public.order_items for delete to authenticated using(public.is_admin());
create policy "recovery visible by owner or admin" on public.recoveries for select to authenticated using(collected_by=auth.uid() or public.is_admin());
create policy "admin manage recoveries" on public.recoveries for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "activities visible by user or admin" on public.activities for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy "activities insert own" on public.activities for insert to authenticated with check(user_id=auth.uid());
create policy "admin manage activities" on public.activities for all to authenticated using(public.is_admin()) with check(public.is_admin());

revoke all on public.customer_code_counters from anon,authenticated;
grant select on public.profiles,public.customers,public.products,public.orders,public.order_items,public.recoveries,public.sectors,public.areas,public.activities to authenticated;
grant insert,update,delete on public.customers,public.products,public.orders,public.order_items,public.recoveries,public.sectors,public.areas to authenticated;

notify pgrst,'reload schema';
