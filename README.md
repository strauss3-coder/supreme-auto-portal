# Supreme Auto Portal

A private management portal for the Supreme Auto website. One HTML file, no build step, no dependencies.

## The files

| File | What it is |
| --- | --- |
| `index.html` | The whole portal. Open it in any browser. |
| `supabase-schema-plain.sql` | **Run this one** in Supabase. No comments, so nothing can be mangled by autocorrect. |
| `supabase-schema.sql` | The same SQL fully commented, for reading. |
| `README.md` | This guide. |

## Signing in

There is **no local portal password**. Access is Supabase Authentication only, using the account you created under Authentication -> Users. The old `supreme` password and all local password logic have been removed.

- Sign in with your email and password. Under the hood this posts to `/auth/v1/token?grant_type=password`, which is exactly what the `signInWithPassword()` SDK call does. The portal talks to the REST endpoint directly so it can stay a single file with no SDK.
- Your session is stored and **survives a refresh**, so you land straight back in the dashboard.
- No session means the login screen, always. The portal cannot be opened without one.
- Tokens are renewed automatically before they lapse. If a session does expire, you are returned to the login screen with an explanation.
- **Sign out** is in the bottom left of the sidebar, and also in Settings. It calls Supabase to revoke the token.
- **Forgot your password** on the login screen sends a Supabase reset email.
- Change your password in **Settings -> Your account**. It updates your Supabase account, not a local file.

One consequence worth knowing: signing in needs internet, because Supabase does the authenticating. Once you have a session you can keep working offline and changes queue up until the signal returns.

## Going live, step by step

Your project already exists and the portal already has its credentials built in, so you can skip straight to step 1.

| | |
| --- | --- |
| Project URL | `https://wltrdchewowvolushyfl.supabase.co` |
| Publishable key | `sb_publishable_1frBQ7n0x2addaHtmGJ6ww_BbyaDiIU` |

Verified on 15 August 2026: the project responds, the key is valid, and the database is still empty.

### 1. Run the schema

In the portal, open **Database** and click **Copy the schema**. Then in Supabase open **SQL Editor -> New query**, paste, and click **Run**. Safe to run more than once.

Use the copy button rather than opening a file and selecting the text. Run `supabase-schema-plain.sql` if you prefer working from the file. Both are free of `--` comment lines on purpose, because editors like Notes and Word autocorrect a double dash into a single dash or an em dash, which turns a comment into broken SQL. That is what caused the `syntax error at or near "SUPREME"` on the first attempt.

`supabase-schema.sql` is the same SQL with full explanatory comments. Read that one, run the plain one.

If the storage section fails with a message about not owning the table, skip it and create three public buckets by hand under **Storage**: `vehicle-images`, `gallery`, `branding`. Tick **Public bucket** on each.

### 2. Create your login

**Authentication -> Users -> Add user.** Use a real email address and a strong password, and **tick Auto Confirm User**. Without that tick you cannot sign in until the confirmation email is clicked.

### 3. Put yourself on the owner allowlist

Nothing works until you do this, which is deliberate. Run this in the SQL Editor with your own email address:

```sql
insert into public.portal_owners (user_id, email)
select id, email from auth.users
where email = 'you@yourdomain.co.za'
on conflict (user_id) do nothing;

select email, added_at from public.portal_owners;
```

That last line must return exactly one row.

### 4. Turn off public signups

**Authentication -> Sign In / Providers -> Email -> turn OFF "Allow new users to sign up".**

This is currently switched ON in your project. Your publishable key sits in your website's source code where anyone can read it, so with signups open a stranger can register an account. The allowlist in step 3 means such an account still sees nothing, but there is no reason to let it exist.

### 5. Sign in

The project URL and key are already built into the portal, so there is nothing to connect. Just open `index.html` and sign in with the account from step 2. Then open **Database** and click **Push my content to the database**.

The pill in the top right now reads **Synced**. Click it any time to see status or force a sync.

### 6. Make the website read the data

**This is the part that is not done yet, and it is the only part that changes what visitors see.** Connecting the portal does nothing to supremeautonorth.co.za on its own. The website has to be changed to fetch its vehicles from Supabase instead of whatever it uses today.

The portal gives you the code. Open **Database** and click **Copy both snippets**. A vehicle listing page needs about ten lines:

```js
const res = await fetch(SUPABASE_URL + '/rest/v1/website_vehicles?select=*',
  { headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY } });
const cars = await res.json();
```

`website_vehicles` is a database view that already hides archived stock and sorts featured vehicles first, so the website never needs to know the rules.

Point your contact form at the `enquiries` table the same way and messages land in the portal's Enquiries page automatically.

## About the publishable key

The publishable key belongs in your website's source code. That is what it is for, and it is why it is safe to keep in `index.html`. Two things protect your data rather than secrecy:

1. **Row level security.** A visitor can read published vehicles, testimonials and live offers, and can submit one enquiry. They cannot read enquiries or change anything.
2. **The owner allowlist.** Changing content needs a signed in account whose id is in `portal_owners`. Signing in is not sufficient on its own.

Never put a **secret** key (`sb_secret_...`) or the legacy **service_role** key in website code or in this portal. Those ignore every security rule above. If one is ever exposed, rotate it in Project Settings -> API keys.

## The sample content

The portal ships with 16 placeholder records: 6 vehicles, 3 testimonials, 2 offers and 5 enquiries. **These are invented.** The customer names, the reviews, the phone numbers, the descriptions and the BMW's VIN are all made up. They exist so the portal does not look empty on first open.

Every one of them carries a red **Sample** badge, and they are excluded from every push to the database. Delete them with one button on the **Database** page before you go live.

Only these details came from the real website and are accurate: the phone and WhatsApp numbers, the email address, the street address, the trading hours, the three social handles, the tagline, and the BMW 320d's headline figures.

The homepage statistics (850+ sold, 12 years, 1,200+ customers, 4.9 rating) and every analytics figure are placeholders too. Replace them with real numbers or remove them. Do not advertise figures you cannot support, and never publish a review a customer did not write.

## How syncing behaves

Changes save to the browser first, then upload. If the internet drops the pill turns orange, changes queue up, and they are sent automatically when the signal returns. Nothing is lost by closing the laptop mid edit.

Signing in pulls the latest copy from the database, so two devices stay in step. If two people edit the same record at the same time, the last save wins. There is no merge.

Photos are resized to 1500px and uploaded to Storage. Photos added before you connected the database live only in that browser, so re upload them on each vehicle once you are connected.

## Adding a new section later

Pages register themselves. Nothing else needs touching, the sidebar and router pick it up:

```js
Portal.register({
  id:'finance', title:'Finance Applications', icon:'briefcase', group:'Customers',
  render(){ return '<h2>Applications</h2>'; },
  mount(root){ /* wire up buttons */ }
});
```

To sync a new section to the database, add a table to the schema and an entry to the `MAP` object describing how portal fields map to database columns.

## What is still missing

- The website itself does not read from Supabase yet. Step 6 above.
- The schema has not been executed yet, so it is unverified against a real Postgres. If a statement errors when you run it, the message will say which line.
- Analytics is placeholder data. Real figures need Google Analytics or Plausible wired in.
- No image cropping. Photos are resized but not cropped.
- No audit trail of who changed what, since there is only one account.
- Signing in requires internet. Resuming an existing session does not.
