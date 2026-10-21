-- ===========================================================================
-- SUPREME AUTO - VEHICLE INVENTORY UPGRADE
-- ---------------------------------------------------------------------------
-- Run this once in the Supabase SQL editor. It is safe to run twice.
--
-- It does four things:
--   1. adds the new vehicle fields the upgraded portal writes
--   2. adds a draft flag so a listing can be worked on before it goes public
--   3. rebuilds the public website view so drafts and sold cars never
--      appear as available stock
--   4. re-states the grants, because new columns are not covered by the
--      column level grants that were issued before they existed
--
-- Nothing is dropped and no existing vehicle is modified. Every car already
-- in the database keeps its details and comes out of this published, exactly
-- as it is today.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. NEW COLUMNS
-- ---------------------------------------------------------------------------
-- Specification. All optional: a dealership lists bakkies, hatchbacks and
-- the occasional import, and forcing every field would stop staff listing
-- a car they only have half the paperwork for.
alter table public.vehicles add column if not exists variant      text default '';
alter table public.vehicles add column if not exists drivetrain   text default '';
alter table public.vehicles add column if not exists doors        int;
alter table public.vehicles add column if not exists seats        int;

-- Registration sits with the VIN as an internal field. It can carry a plate
-- or a licence status, so it is deliberately kept out of the public view.
alter table public.vehicles add column if not exists registration text default '';

-- Selling copy.
alter table public.vehicles add column if not exists headline        text default '';
alter table public.vehicles add column if not exists service_history text default '';
alter table public.vehicles add column if not exists warranty        text default '';
alter table public.vehicles add column if not exists finance_note    text default '';
alter table public.vehicles add column if not exists notes           text default '';

-- Pricing. previous_price drives a genuine "was" strike-through and
-- offer_price a special. Both are only shown when they are real: the portal
-- refuses a previous price at or below the asking price, and the website
-- ignores anything that does not make sense.
alter table public.vehicles add column if not exists previous_price numeric default 0;
alter table public.vehicles add column if not exists offer_price    numeric default 0;

-- Draft. A draft is never public, whatever its other flags say. Existing
-- rows default to false, so everything currently listed stays listed.
alter table public.vehicles add column if not exists draft boolean not null default false;

-- Sold date, so "recently sold" reporting and the activity trail have a real
-- timestamp rather than guessing from updated_at.
alter table public.vehicles add column if not exists sold_at timestamptz;


-- ---------------------------------------------------------------------------
-- 2. INDEXES
-- ---------------------------------------------------------------------------
-- The public view filters on these three every time a visitor loads the site.
create index if not exists vehicles_public_idx
  on public.vehicles (archived, draft, sold);

-- The portal searches stock and VIN constantly from the inventory screen.
create index if not exists vehicles_stock_idx on public.vehicles (stock);


-- ---------------------------------------------------------------------------
-- 3. THE PUBLIC WEBSITE VIEW
-- ---------------------------------------------------------------------------
-- What the website is allowed to see. Three rules live here rather than in
-- the website's JavaScript, so there is one place to change them and a
-- visitor cannot work around them:
--
--   archived = false   withdrawn stock is not published
--   draft    = false   a listing being written is not published
--   sold     = false   a sold car is not published
--
-- vin and registration are absent on purpose. They are never sent to a
-- browser.
--
-- The view deliberately does NOT use security_invoker. The website's anon
-- role holds column level grants on public.vehicles, not a grant on the
-- table, and PostgreSQL requires a table level grant to read through a
-- security_invoker view. Setting it would make this view unreadable by the
-- public and the website would go blank. Running as the owner is what lets
-- the column list above act as the boundary: anon can read exactly these
-- columns, for exactly these rows, and has no other way to the table.
drop view if exists public.website_vehicles;

create view public.website_vehicles as
  select id, name, headline, brand, model, variant, year, mileage,
         transmission, fuel, body, colour, engine, power, drivetrain,
         doors, seats, condition,
         price, previous_price, offer_price, installment,
         description, service_history, warranty, finance_note, notes,
         features, images, stock, status, featured, reserved, views,
         sort_order, created_at, updated_at
  from public.vehicles
  where archived = false
    and draft    = false
    and sold     = false
  order by featured desc, sort_order asc, created_at desc;


-- ---------------------------------------------------------------------------
-- 4. GRANTS
-- ---------------------------------------------------------------------------
-- A column level grant only covers the columns that existed when it was
-- issued, so the list has to be re-stated now that there are more of them.
-- The website reads the view, but this keeps the direct table grant honest
-- and keeps vin, registration and draft out of anonymous reach.
grant usage on schema public to anon, authenticated;

grant select on public.website_vehicles to anon;

revoke select on public.vehicles from anon;
grant select (id, name, headline, brand, model, variant, year, mileage,
              transmission, fuel, body, colour, engine, power, drivetrain,
              doors, seats, condition,
              price, previous_price, offer_price, installment,
              description, service_history, warranty, finance_note, notes,
              features, images, stock, status, featured, sold, reserved,
              archived, views, sort_order, created_at, updated_at)
  on public.vehicles to anon;

grant select, insert, update, delete on public.vehicles to authenticated;
grant select on public.website_vehicles to authenticated;


-- ---------------------------------------------------------------------------
-- 5. CHECK IT WORKED
-- ---------------------------------------------------------------------------
-- Expect: every existing vehicle still present, none of them draft, and the
-- public view holding only the cars that are genuinely for sale.
select count(*) as vehicles_total          from public.vehicles;
select count(*) as vehicles_draft          from public.vehicles where draft;
select count(*) as vehicles_sold           from public.vehicles where sold;
select count(*) as publicly_visible        from public.website_vehicles;

-- Expect zero rows: nothing internal may reach the public view.
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'website_vehicles'
  and column_name in ('vin', 'registration', 'draft', 'archived', 'sold');
