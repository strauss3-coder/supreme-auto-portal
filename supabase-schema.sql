-- ============================================================================
-- SUPREME AUTO PORTAL - Supabase schema
-- ----------------------------------------------------------------------------
-- Run this once in your Supabase project.
-- Dashboard  ->  SQL Editor  ->  New query  ->  paste all of this  ->  Run.
--
-- It is safe to run more than once. Every statement checks first.
--
-- Design notes
--   * Primary keys are text, not uuid, because the portal generates its own
--     ids. That keeps the portal and the database in step with no mapping.
--   * Website visitors (the "anon" role) may READ vehicles, testimonials,
--     offers and settings, and may INSERT an enquiry. Nothing else.
--   * Changing content or reading enquiries needs a signed in account that
--     is ALSO on the portal_owners allowlist. Being signed in is not enough,
--     because your publishable key is public and signups can be left open.
--   * Photos live in Storage buckets, not in table rows. Only their public
--     URLs are stored here.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------------

-- Single row per settings document: homepage, contact, appearance, meta,
-- analytics, gallery. The portal reads and writes these as whole documents.
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
  source      text not null default 'Direct',
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

-- Website visitors may insert here. They may never read it back.
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

-- Helpful indexes for the public website's queries.
create index if not exists vehicles_public_idx
  on public.vehicles (archived, sold, featured, sort_order);
create index if not exists vehicles_created_idx
  on public.vehicles (created_at desc);
create index if not exists enquiries_status_idx
  on public.enquiries (status, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. UPDATED_AT TRIGGER
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 3. WHO COUNTS AS AN OWNER
-- ---------------------------------------------------------------------------
-- Your publishable key lives in your website's source code, so treat it as
-- public knowledge. That means "is this request signed in?" is not a strong
-- enough test on its own: if account signups are ever left open, a stranger
-- could register and would then pass it.
--
-- So the portal trusts an explicit allowlist instead. Only user ids listed
-- in portal_owners may read enquiries or change content. An account that is
-- not on the list can sign in and still see nothing.
create table if not exists public.portal_owners (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  email     text,
  added_at  timestamptz not null default now()
);

alter table public.portal_owners enable row level security;

-- security definer lets this check the allowlist without the caller needing
-- read access to it. The fixed search_path stops the function being tricked
-- into reading some other table called portal_owners.
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

-- ---------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
alter table public.site_settings enable row level security;
alter table public.vehicles      enable row level security;
alter table public.testimonials  enable row level security;
alter table public.offers        enable row level security;
alter table public.enquiries     enable row level security;
alter table public.activity_log  enable row level security;

-- Clear any previous versions of these policies so the script can be rerun.
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

-- An owner may confirm their own membership. Nobody may edit the list from
-- the outside: adding an owner is done in the SQL Editor, on purpose.
create policy "owner reads own membership" on public.portal_owners
  for select to authenticated using (user_id = auth.uid());

-- Public website: read only, and only the content meant to be seen.
create policy "public reads settings"     on public.site_settings for select to anon
  using (key in ('homepage','contact','appearance','gallery'));
create policy "public reads vehicles"     on public.vehicles      for select to anon using (archived = false);
create policy "public reads testimonials" on public.testimonials  for select to anon using (true);
create policy "public reads live offers"  on public.offers        for select to anon
  using (active = true and (expiry is null or expiry > now()));

-- Public website: may submit an enquiry, may never read or change one.
create policy "public submits enquiry" on public.enquiries for insert to anon with check (true);

-- The portal, once signed in AS A LISTED OWNER, may do everything.
-- A signed in account that is not on the allowlist gets nothing at all.
create policy "owner manages settings"     on public.site_settings for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages vehicles"     on public.vehicles      for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages testimonials" on public.testimonials  for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages offers"       on public.offers        for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages enquiries"    on public.enquiries     for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "owner manages activity"     on public.activity_log  for all to authenticated using (public.is_owner()) with check (public.is_owner());

-- ---------------------------------------------------------------------------
-- 5. STORAGE BUCKETS FOR PHOTOS
-- ---------------------------------------------------------------------------
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

-- Anyone may view a photo. Only a listed owner may add, replace or delete one.
create policy "supreme public read" on storage.objects for select to anon, authenticated
  using (bucket_id in ('vehicle-images','gallery','branding'));
create policy "supreme owner insert" on storage.objects for insert to authenticated
  with check (bucket_id in ('vehicle-images','gallery','branding') and public.is_owner());
create policy "supreme owner update" on storage.objects for update to authenticated
  using (bucket_id in ('vehicle-images','gallery','branding') and public.is_owner());
create policy "supreme owner delete" on storage.objects for delete to authenticated
  using (bucket_id in ('vehicle-images','gallery','branding') and public.is_owner());

-- ---------------------------------------------------------------------------
-- 6. VIEW USED BY THE PUBLIC WEBSITE
-- ---------------------------------------------------------------------------
-- Convenience view so the website never has to know the filter rules.
-- Ordered the way the portal orders them.
--
-- security_invoker makes the view obey the row level security of whoever
-- queries it, rather than the view owner. Without it a view can quietly
-- hand out rows the policies above were meant to withhold.
-- It needs Postgres 15 or newer, which every current Supabase project runs.
-- If your project is older, drop the "with" line and the filter below
-- still protects archived stock.
create or replace view public.website_vehicles
  with (security_invoker = true) as
  select id, name, brand, model, year, mileage, transmission, fuel, body,
         colour, engine, power, condition, price, installment, description,
         features, images, stock, status, featured, sold, reserved, views,
         sort_order, created_at
  from public.vehicles
  where archived = false
  order by featured desc, sort_order asc, created_at desc;

-- ---------------------------------------------------------------------------
-- 7. GRANTS
-- ---------------------------------------------------------------------------
-- Row level security decides which ROWS a role may touch. Grants decide
-- which TABLES it may touch at all. Both are needed. Supabase usually sets
-- these by default, but stating them makes the script safe on any project.
grant usage on schema public to anon, authenticated;

grant select on public.site_settings, public.testimonials,
                public.offers, public.website_vehicles to anon;

revoke select on public.vehicles from anon;
grant select (id, name, brand, model, year, mileage, transmission, fuel, body, colour,
           engine, power, condition, price, installment, description, features,
           images, stock, status, featured, sold, reserved, archived, views,
           sort_order, created_at)
  on public.vehicles to anon;
grant insert on public.enquiries to anon;

grant select, insert, update, delete
  on public.site_settings, public.vehicles, public.testimonials,
     public.offers, public.enquiries, public.activity_log to authenticated;
grant select on public.website_vehicles, public.portal_owners to authenticated;

-- ---------------------------------------------------------------------------
-- IF SECTION 5 FAILS
--   Some projects refuse "create policy ... on storage.objects" from the SQL
--   Editor with a message about not being the owner of the table. If that
--   happens, skip section 5 and set the buckets up by hand instead:
--     Storage -> New bucket -> name it vehicle-images -> tick Public bucket.
--     Repeat for gallery and branding.
--   Public buckets already allow anyone to view a photo and only signed in
--   users to upload, which is exactly what section 4 was asking for.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- DONE WITH THE SCHEMA. Three steps left, and step 2 is not optional.
--
--   1. Authentication -> Users -> Add user.
--      Use a real email address and a strong password.
--      Tick "Auto Confirm User", otherwise you cannot sign in until the
--      confirmation email is clicked.
--
--   2. Put yourself on the owner allowlist. Nothing works until you do,
--      and that is deliberate: an account that is not listed sees nothing.
--      Run this in the SQL Editor with your own email address:
--
--        insert into public.portal_owners (user_id, email)
--        select id, email from auth.users
--        where email = 'you@yourdomain.co.za'
--        on conflict (user_id) do nothing;
--
--      Check it worked. This must return exactly one row:
--
--        select email, added_at from public.portal_owners;
--
--   3. Authentication -> Sign In / Providers -> Email -> turn OFF
--      "Allow new users to sign up".
--      Your publishable key sits in your website's source code where anyone
--      can read it. With signups open, a stranger can create an account in
--      your project. The allowlist above means such an account still sees
--      nothing, but there is no reason to let it exist at all.
--
-- Then open the portal, go to Database, paste your Project URL and
-- publishable key, and sign in with the account from step 1.
-- ---------------------------------------------------------------------------
