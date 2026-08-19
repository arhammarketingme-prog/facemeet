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

## Phase 2 (now included)

Run `supabase/schema_phase2.sql` **after** `schema.sql`, in the same SQL
editor. It adds:

- `posts`, `follows`, `likes`, `comments` tables
- triggers that keep `likes_count`/`comments_count` on posts and
  `channel_followers_count`/`channel_posts_count` on profiles in sync
  automatically — the frontend never hand-updates these counters
- RLS policies: posts/follows/likes/comments are publicly readable; a user
  can only create/delete rows where they are the actor (author, follower, or
  liker)

The frontend (`index.html`) now has a logged-in app shell with three tabs:

- **Home** — composer + feed of all active posts, with like/unlike,
  expandable comments, and a follow/unfollow button on other people's posts
- **Search** — debounced search across people (username/display name) and
  post content
- **Profile** — unchanged from Phase 1 (channel name, bio, referral code)

## Phase 3 (now included)

Run `supabase/schema_phase3.sql` **after** `schema.sql` and
`schema_phase2.sql`. It adds:

- `communities`, `community_members` — plus `posts.community_id` (nullable)
  so any post can optionally belong to a community
- `polls`, `poll_options`, `poll_votes` — one vote per user per poll,
  enforced by a primary key, with a trigger keeping `votes_count` in sync
- `notifications` — written only by security-definer trigger functions
  (follow, like, comment) so the client can never forge one; the recipient
  can read and mark their own as read, nothing else

New in the frontend:

- **Communities tab** — create a community, browse/join others, open one to
  see its own feed
- **Composer** — a "Post to" dropdown (your feed or any community you've
  joined) and a poll toggle (question + 2–4 options)
- **Alerts tab** — follows/likes/comments notifications, with an unread dot
  on the tab; opening the tab marks them read
- Polls appear inline in the Home feed (and inside a community's feed);
  tapping an option votes once and reveals live percentages

## What's not yet built

Demo/seed accounts, YouTube discovery, Earn Center, advertising, E2E
encrypted messaging, admin dashboard, moderation, multilingual UI — later
phases per the roadmap.

## Next phase

Phase 4 per the roadmap: 1,000 demo/AI seed accounts, demo content, demo
communities, demo analytics, demo earnings — so the platform doesn't launch
empty.
