begin;

alter table public.testimonials
  add column if not exists source text not null default 'Direct';

revoke select on public.vehicles from anon;
grant select (id, name, brand, model, year, mileage, transmission, fuel, body,
              colour, engine, power, condition, price, installment, description,
              features, images, stock, status, featured, sold, reserved,
              archived, views, sort_order, created_at)
  on public.vehicles to anon;

drop policy if exists "public reads settings" on public.site_settings;
create policy "public reads settings" on public.site_settings for select to anon
  using (key in ('homepage','contact','appearance','gallery'));

commit;
