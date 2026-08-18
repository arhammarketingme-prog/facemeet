# Nexus — Phase 1 (Foundation)

"Create. Connect. Grow. Earn." — a privacy-first social platform.

This is **Phase 1 only**, from the roadmap: authentication, database, Row Level
Security, and profiles. Everything else (feed, communities, polls, YouTube
discovery, Earn Center, ads, demo mode, E2E messaging...) ships in later
phases on top of this base — building all of it at once produces something
untestable and unmaintainable, so it's being built in the order the spec
itself lays out under "Development Phases."

## What's here

- `index.html` — single-file frontend: landing hero, signup/login/logout, profile view + edit
- `supabase/schema.sql` — `profiles` table, auto-create-on-signup trigger, RLS policies

## Setup

1. **Create a Supabase project** at supabase.com.
2. **Run the schema**: open the SQL editor in your Supabase dashboard, paste
   the contents of `supabase/schema.sql`, and run it. This creates the
   `profiles` table, a trigger that auto-creates a profile row (with a
   channel name and referral code) whenever someone signs up, and RLS
   policies so:
   - anyone can read active profiles (they're public by design)
   - a user can only update their own row
   - no client can insert a profile row directly — only the trigger can
3. **Get your keys**: Project Settings → API. You need the **Project URL**
   and the **anon public key**.
4. **Wire up the frontend**: open `index.html` and replace:
   ```js
   const SUPABASE_URL = 'YOUR_SUPABASE_URL';
   const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
   ```
   The anon key is safe to expose in frontend code — Row Level Security is
   what actually controls access, not key secrecy. **Never** put your
   service-role key in this file or in any frontend code, ever.
5. **Email confirmation**: by default Supabase requires email confirmation
   before a session is issued. You can turn this off for local testing under
   Authentication → Settings → "Confirm email", but leave it on for
   production.

## Deploy

No build step — push this folder to a GitHub repo and connect it to
Cloudflare Pages as a static site (build command: none, output directory:
`/`). Done.

## What Phase 1 does and doesn't do

Works end to end: signup, login, logout, session persistence, profile view,
profile edit (channel name + bio), referral code generation.

Not yet built (later phases per the roadmap): posts/feed, follow, likes/
comments, communities, polls, notifications, demo/seed accounts, YouTube
discovery, Earn Center, advertising, E2E encrypted messaging, admin
dashboard, moderation, multilingual UI.

## Next phase

Phase 2 per the roadmap: posts, feed, likes, comments, follow, search. That
needs a few more tables (`posts`, `follows`, `likes`, `comments`) and RLS
policies for each — say the word and it's the next migration.
