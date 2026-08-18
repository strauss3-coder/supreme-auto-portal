/* ===========================================================================
   SUPREME AUTO - final setup. Run this once in the Supabase SQL Editor.

   BEFORE YOU RUN IT, create the login:
     Authentication -> Users -> Add user
       Email     supremea1auto@gmail.com
       Password  (the one you chose)
       Tick      Auto Confirm User          <- without this you cannot sign in

   Then paste this whole file into SQL Editor -> New query -> Run.
   Safe to run more than once.

   Every comment here is a block comment on purpose. Editors such as Notes
   and Word autocorrect a double dash into an em dash, which turns a line
   comment into broken SQL. Block comments cannot be mangled that way.
   =========================================================================== */

begin;

/* ===========================================================================
   1. Close the VIN leak.

   The portal tells the user the VIN field is private. It is not: anon can
   read it straight off the vehicles table. The website reads the
   website_vehicles view, which never exposed vin, so this changes nothing
   a visitor sees.

   A column level grant is used rather than a plain revoke because the view
   runs with security_invoker, so the caller still needs SELECT on the
   columns the view actually references.
   =========================================================================== */
revoke select on public.vehicles from anon;
grant select (id, name, brand, model, year, mileage, transmission, fuel, body,
              colour, engine, power, condition, price, installment, description,
              features, images, stock, status, featured, sold, reserved,
              archived, views, sort_order, created_at)
  on public.vehicles to anon;

/* ===========================================================================
   2. Stop publishing settings the website never asks for.
   js/site-content.js reads only the homepage and contact documents.
   =========================================================================== */
drop policy if exists "public reads settings" on public.site_settings;
create policy "public reads settings" on public.site_settings for select to anon
  using (key in ('homepage','contact'));

/* ===========================================================================
   3. Put the dealership account on the owner allowlist.

   Signing in is deliberately not enough on its own. Without this row the
   account signs in successfully and sees an empty portal.
   =========================================================================== */
insert into public.portal_owners (user_id, email)
select id, email from auth.users
where email = 'supremea1auto@gmail.com'
on conflict (user_id) do nothing;

commit;

/* ===========================================================================
   CHECKS. Read the three results below before you close this tab.
   =========================================================================== */

/* A. Must return exactly one row. If it returns none, the Add user step in
      Authentication was missed, or the email does not match character for
      character. Note the "a1" in supremea1auto. */
select email, added_at from public.portal_owners;

/* B. Must return 27 rows and must NOT contain vin. */
select column_name
from information_schema.column_privileges
where grantee = 'anon' and table_name = 'vehicles' and privilege_type = 'SELECT'
order by column_name;

/* C. Must return only homepage and contact. */
select key from public.site_settings order by key;

/* ===========================================================================
   AFTER RUNNING, two things left:

   1. Authentication -> Sign In / Providers -> Email
      Turn OFF "Allow new users to sign up".
      The publishable key sits in the website source, so with signups open
      a stranger can register an account in this project.

   2. Confirm the VIN leak is closed. In a browser, this must now fail
      rather than return data:

      https://wltrdchewowvolushyfl.supabase.co/rest/v1/vehicles?select=vin&apikey=sb_publishable_1frBQ7n0x2addaHtmGJ6ww_BbyaDiIU
   =========================================================================== */
