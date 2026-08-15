create table if not exists public.site_settings (
  key         text primary key,
  value       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

create table if not exists public.vehicles (
  id            text primary key,
  name          text not null default '',
  brand         text default '',
  model         text default '',
  year          int,
  mileage       int default 0,
  transmission  text default '',
  fuel          text default '',
  body          text default '',
  colour        text default '',
  engine        text default '',
  power         text default '',
  condition     text default '',
  price         numeric default 0,
  installment   numeric default 0,
  description   text default '',
  features      jsonb not null default '[]'::jsonb,
  images        jsonb not null default '[]'::jsonb,
  vin           text default '',
  stock         text default '',
  status        text default 'available',
  featured      boolean not null default false,
  sold          boolean not null default false,
  reserved      boolean not null default false,
  archived      boolean not null default false,
  views         int not null default 0,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.testimonials (
  id          text primary key,
  name        text not null default '',
  vehicle     text default '',
  rating      int not null default 5 check (rating between 1 and 5),
  review      text default '',
  photo       text default '',
  featured    boolean not null default false,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.offers (
  id           text primary key,
  title        text not null default '',
  description  text default '',
  btn_text     text default '',
  btn_link     text default '',
  colour       text default '#0A84FF',
  image        text default '',
  active       boolean not null default false,
  expiry       timestamptz,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.enquiries (
  id          text primary key,
  name        text not null default '',
  phone       text default '',
  email       text default '',
  vehicle     text default '',
  source      text default 'Website form',
  status      text not null default 'unread',
  message     text default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.activity_log (
  id      text primary key,
  title   text default '',
  detail  text default '',
  icon    text default 'activity',
  tone    text default '',
  at      timestamptz not null default now()
);

create index if not exists vehicles_public_idx
  on public.vehicles (archived, sold, featured, sort_order);
create index if not exists vehicles_created_idx
  on public.vehicles (created_at desc);
create index if not exists enquiries_status_idx
  on public.enquiries (status, created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['site_settings','vehicles','testimonials','offers','enquiries']
  loop
    execute format('drop trigger if exists touch_%1$s on public.%1$s', t);
    execute format(
      'create trigger touch_%1$s before update on public.%1$s
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

create table if not exists public.portal_owners (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  email     text,
  added_at  timestamptz not null default now()
);

alter table public.portal_owners enable row level security;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.portal_owners where user_id = auth.uid()
  );
$$;

revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;

alter table public.site_settings enable row level security;
alter table public.vehicles      enable row level security;
alter table public.testimonials  enable row level security;
alter table public.offers        enable row level security;
alter table public.enquiries     enable row level security;
alter table public.activity_log  enable row level security;

do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('site_settings','vehicles','testimonials','offers','enquiries','activity_log','portal_owners')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

create policy "owner reads own membership" on public.portal_owners
  for select to authenticated using (user_id = auth.uid());

create policy "public reads settings"     on public.site_settings for select to anon using (true);
create policy "public reads vehicles"     on public.vehicles      for select to anon using (archived = false);
create policy "public reads testimonials" on public.testimonials  for select to anon using (true);
create policy "public reads live offers"  on public.offers        for select to anon
  using (active = true and (expiry is null or expiry > now()));

create policy "public submits enquiry" on public.enquiries for insert to anon with check (true);

create policy "owner manages settings"     on public.site_settings for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages vehicles"     on public.vehicles      for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages testimonials" on public.testimonials  for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages offers"       on public.offers        for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages enquiries"    on public.enquiries     for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages activity"     on public.activity_log  for all to authenticated using (public.is_owner()) with check (public.is_owner());

insert into storage.buckets (id, name, public)
values ('vehicle-images','vehicle-images',true),
       ('gallery','gallery',true),
       ('branding','branding',true)
on conflict (id) do update set public = true;

do $$
declare r record;
begin
  for r in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like 'supreme %'
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy "supreme public read" on storage.objects for select to anon, authenticated
  using (bucket_id in ('vehicle-images','gallery','branding'));
create policy "supreme owner insert" on storage.objects for insert to authenticated
  with check (bucket_id in ('vehicle-images','gallery','branding') and public.is_owner());
create policy "supreme owner update" on storage.objects for update to authenticated
  using (bucket_id in ('vehicle-images','gallery','branding') and public.is_owner());
create policy "supreme owner delete" on storage.objects for delete to authenticated
  using (bucket_id in ('vehicle-images','gallery','branding') and public.is_owner());

create or replace view public.website_vehicles
  with (security_invoker = true) as
  select id, name, brand, model, year, mileage, transmission, fuel, body,
         colour, engine, power, condition, price, installment, description,
         features, images, stock, status, featured, sold, reserved, views,
         sort_order, created_at
  from public.vehicles
  where archived = false
  order by featured desc, sort_order asc, created_at desc;

grant usage on schema public to anon, authenticated;

grant select on public.site_settings, public.vehicles, public.testimonials,
                public.offers, public.website_vehicles to anon;
grant insert on public.enquiries to anon;

grant select, insert, update, delete
  on public.site_settings, public.vehicles, public.testimonials,
     public.offers, public.enquiries, public.activity_log to authenticated;
grant select on public.website_vehicles, public.portal_owners to authenticated;
