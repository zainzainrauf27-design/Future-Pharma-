-- FUTURE PHARMA: separate official location hierarchy from pharma sales sectors.
-- Safe/additive: existing customers, sectors and areas are preserved.
-- Run this file once in Supabase SQL Editor after migration_eorder_book.sql.

create table if not exists public.punjab_divisions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.punjab_districts (
  id uuid primary key default gen_random_uuid(),
  division_id uuid not null references public.punjab_divisions(id) on delete restrict,
  name text not null,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (division_id, name)
);

create table if not exists public.punjab_tehsils (
  id uuid primary key default gen_random_uuid(),
  district_id uuid not null references public.punjab_districts(id) on delete restrict,
  name text not null,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (district_id, name)
);

create table if not exists public.punjab_localities (
  id uuid primary key default gen_random_uuid(),
  tehsil_id uuid not null references public.punjab_tehsils(id) on delete restrict,
  name text not null,
  kind text not null default 'Locality',
  code text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tehsil_id, name)
);

create index if not exists punjab_districts_division_idx on public.punjab_districts(division_id, name);
create index if not exists punjab_tehsils_district_idx on public.punjab_tehsils(district_id, name);
create index if not exists punjab_localities_tehsil_idx on public.punjab_localities(tehsil_id, name);

alter table public.customers add column if not exists division_id uuid references public.punjab_divisions(id) on delete set null;
alter table public.customers add column if not exists district_id uuid references public.punjab_districts(id) on delete set null;
alter table public.customers add column if not exists tehsil_id uuid references public.punjab_tehsils(id) on delete set null;
alter table public.customers add column if not exists locality_id uuid references public.punjab_localities(id) on delete set null;

-- Current district list is based on PLGA 2025 district demarcation notifications.
-- Existing areas include Murree, Talagang, Wazirabad, Kot Addu and Taunsa as districts.
insert into public.punjab_divisions(name, code) values
 ('Bahawalpur','PB-DIV-BAH'),('Dera Ghazi Khan','PB-DIV-DGK'),('Faisalabad','PB-DIV-FSD'),
 ('Gujranwala','PB-DIV-GRW'),('Lahore','PB-DIV-LHE'),('Multan','PB-DIV-MTN'),
 ('Rawalpindi','PB-DIV-RWP'),('Sahiwal','PB-DIV-SWL'),('Sargodha','PB-DIV-SGD')
on conflict (code) do update set name=excluded.name;

insert into public.punjab_districts(division_id,name,code)
select d.id,x.name,x.code from (values
 ('Bahawalpur','Bahawalnagar','PB-DST-BWN'),('Bahawalpur','Bahawalpur','PB-DST-BWP'),('Bahawalpur','Rahim Yar Khan','PB-DST-RYK'),
 ('Dera Ghazi Khan','Dera Ghazi Khan','PB-DST-DGK'),('Dera Ghazi Khan','Layyah','PB-DST-LAY'),('Dera Ghazi Khan','Muzaffargarh','PB-DST-MZG'),('Dera Ghazi Khan','Rajanpur','PB-DST-RJP'),('Dera Ghazi Khan','Taunsa','PB-DST-TNS'),('Dera Ghazi Khan','Kot Addu','PB-DST-KAD'),
 ('Faisalabad','Chiniot','PB-DST-CHI'),('Faisalabad','Faisalabad','PB-DST-FSD'),('Faisalabad','Jhang','PB-DST-JHG'),('Faisalabad','Toba Tek Singh','PB-DST-TTS'),
 ('Gujranwala','Gujranwala','PB-DST-GRW'),('Gujranwala','Gujrat','PB-DST-GJT'),('Gujranwala','Hafizabad','PB-DST-HFD'),('Gujranwala','Mandi Bahauddin','PB-DST-MBD'),('Gujranwala','Narowal','PB-DST-NRW'),('Gujranwala','Sialkot','PB-DST-SKT'),('Gujranwala','Wazirabad','PB-DST-WZD'),
 ('Lahore','Kasur','PB-DST-KSR'),('Lahore','Lahore','PB-DST-LHE'),('Lahore','Nankana Sahib','PB-DST-NKS'),('Lahore','Sheikhupura','PB-DST-SKP'),
 ('Multan','Khanewal','PB-DST-KHW'),('Multan','Lodhran','PB-DST-LOD'),('Multan','Multan','PB-DST-MTN'),('Multan','Vehari','PB-DST-VHR'),
 ('Rawalpindi','Attock','PB-DST-ATK'),('Rawalpindi','Chakwal','PB-DST-CKL'),('Rawalpindi','Jhelum','PB-DST-JLM'),('Rawalpindi','Rawalpindi','PB-DST-RWP'),('Rawalpindi','Murree','PB-DST-MRE'),('Rawalpindi','Talagang','PB-DST-TLG'),
 ('Sahiwal','Okara','PB-DST-OKR'),('Sahiwal','Pakpattan','PB-DST-PKP'),('Sahiwal','Sahiwal','PB-DST-SWL'),
 ('Sargodha','Bhakkar','PB-DST-BKR'),('Sargodha','Khushab','PB-DST-KHB'),('Sargodha','Mianwali','PB-DST-MNW'),('Sargodha','Sargodha','PB-DST-SGD')
) as x(division_name,name,code)
join public.punjab_divisions d on d.name=x.division_name
on conflict(code) do update set name=excluded.name, division_id=excluded.division_id;

-- Tehsil names seeded from the 2025-current published Punjab list. These are
-- editable in Admin > Punjab locations and can be extended when notifications
-- create or rename an administrative unit.
insert into public.punjab_tehsils(district_id,name,code)
select d.id,x.name,x.code from (values
 ('PB-DST-BWN','Bahawalnagar','PB-TH-BWN-01'),('PB-DST-BWN','Chishtian','PB-TH-BWN-02'),('PB-DST-BWN','Fort Abbas','PB-TH-BWN-03'),('PB-DST-BWN','Haroonabad','PB-TH-BWN-04'),('PB-DST-BWN','Minchinabad','PB-TH-BWN-05'),
 ('PB-DST-BWP','Ahmadpur East','PB-TH-BWP-01'),('PB-DST-BWP','Bahawalpur City','PB-TH-BWP-02'),('PB-DST-BWP','Bahawalpur Saddar','PB-TH-BWP-03'),('PB-DST-BWP','Hasilpur','PB-TH-BWP-04'),('PB-DST-BWP','Khairpur Tamewali','PB-TH-BWP-05'),('PB-DST-BWP','Yazman','PB-TH-BWP-06'),
 ('PB-DST-RYK','Rahim Yar Khan','PB-TH-RYK-01'),('PB-DST-RYK','Sadiqabad','PB-TH-RYK-02'),('PB-DST-RYK','Liaqatpur','PB-TH-RYK-03'),('PB-DST-RYK','Khanpur','PB-TH-RYK-04'),
 ('PB-DST-DGK','Dera Ghazi Khan','PB-TH-DGK-01'),('PB-DST-DGK','Kot Chutta','PB-TH-DGK-02'),('PB-DST-DGK','Muhammadpur','PB-TH-DGK-03'),
 ('PB-DST-LAY','Layyah','PB-TH-LAY-01'),('PB-DST-LAY','Karor Lal Esan','PB-TH-LAY-02'),('PB-DST-LAY','Chaubara','PB-TH-LAY-03'),
 ('PB-DST-MZG','Muzaffargarh','PB-TH-MZG-01'),('PB-DST-MZG','Alipur','PB-TH-MZG-02'),('PB-DST-MZG','Jatoi','PB-TH-MZG-03'),('PB-DST-MZG','Rangpur','PB-TH-MZG-04'),('PB-DST-MZG','Chowk Sarwar Shaheed','PB-TH-MZG-05'),
 ('PB-DST-RJP','Rajanpur','PB-TH-RJP-01'),('PB-DST-RJP','Rojhan','PB-TH-RJP-02'),('PB-DST-RJP','Jampur','PB-TH-RJP-03'),('PB-DST-RJP','Dajal','PB-TH-RJP-04'),('PB-DST-RJP','Jampur Tribal Area','PB-TH-RJP-05'),('PB-DST-RJP','De-Excluded Area Rajanpur','PB-TH-RJP-06'),
 ('PB-DST-TNS','Taunsa','PB-TH-TNS-01'),('PB-DST-TNS','Koh-e-Suleman','PB-TH-TNS-02'),('PB-DST-TNS','Wahova','PB-TH-TNS-03'),
 ('PB-DST-KAD','Kot Addu','PB-TH-KAD-01'),('PB-DST-KAD','Chowk Sarwar Shaheed','PB-TH-KAD-02'),
 ('PB-DST-CHI','Chiniot','PB-TH-CHI-01'),('PB-DST-CHI','Bhowana','PB-TH-CHI-02'),('PB-DST-CHI','Lalian','PB-TH-CHI-03'),
 ('PB-DST-FSD','Faisalabad City','PB-TH-FSD-01'),('PB-DST-FSD','Faisalabad Saddar','PB-TH-FSD-02'),('PB-DST-FSD','Jaranwala','PB-TH-FSD-03'),('PB-DST-FSD','Samundri','PB-TH-FSD-04'),('PB-DST-FSD','Tandlianwala','PB-TH-FSD-05'),('PB-DST-FSD','Chak Jhumra','PB-TH-FSD-06'),
 ('PB-DST-JHG','Jhang','PB-TH-JHG-01'),('PB-DST-JHG','Shorkot','PB-TH-JHG-02'),('PB-DST-JHG','Ahmadpur Sial','PB-TH-JHG-03'),('PB-DST-JHG','Athara Hazari','PB-TH-JHG-04'),('PB-DST-JHG','Mandi Shah Jeewna','PB-TH-JHG-05'),
 ('PB-DST-TTS','Toba Tek Singh','PB-TH-TTS-01'),('PB-DST-TTS','Gojra','PB-TH-TTS-02'),('PB-DST-TTS','Kamalia','PB-TH-TTS-03'),('PB-DST-TTS','Pirmahal','PB-TH-TTS-04'),
 ('PB-DST-GRW','Gujranwala City','PB-TH-GRW-01'),('PB-DST-GRW','Gujranwala Saddar','PB-TH-GRW-02'),('PB-DST-GRW','Kamoke','PB-TH-GRW-03'),('PB-DST-GRW','Nowshera Virkan','PB-TH-GRW-04'),
 ('PB-DST-GJT','Gujrat','PB-TH-GJT-01'),('PB-DST-GJT','Kharian','PB-TH-GJT-02'),('PB-DST-GJT','Sarai Alamgir','PB-TH-GJT-03'),('PB-DST-GJT','Jalalpur Jattan','PB-TH-GJT-04'),('PB-DST-GJT','Kunjah','PB-TH-GJT-05'),
 ('PB-DST-HFD','Hafizabad','PB-TH-HFD-01'),('PB-DST-HFD','Pindi Bhattian','PB-TH-HFD-02'),
