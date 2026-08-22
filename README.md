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

## Phase 4 (now included)

Run `supabase/schema_phase4.sql` **after** phases 1–3. It's a single file
that both creates the demo tables and seeds them — safe to re-run (it
clears prior demo rows first). It creates:

- `demo_accounts`, `demo_posts`, `demo_comments`, `demo_communities` — kept
  completely separate from the real `profiles`/`posts`/`communities`
  tables, per spec §38–41. Demo rows are never linked to `auth.users`, so
  they can never log in or be mistaken for real accounts.
- RLS: public read-only on all four tables. No insert/update/delete policy
  exists for any client role, so only the seed script itself (running with
  owner privileges in the SQL editor) can write to them.
- ~1,000 demo personas across the spec's category list (Technology, AI,
  Business, Maharashtra, Agriculture, Creator Economy, etc.), 1–3 sample
  posts each, a canned comment on ~40% of posts, and ~24 demo communities.
- Every generated bio and post is template-based and explicitly labeled
  "DEMO" / "AI DEMO" / "SAMPLE" — never framed as real news or attributed
  to a real person, per spec §12.

The landing page now shows a live **"Explore the platform — DEMO"** section
(visible to anyone, no login needed) with sample creators, a sample feed,
and sample communities, each card carrying a visible DEMO badge — so a
first-time visitor sees the platform "alive" per spec §57, instead of an
empty page.

## Phase 5 (now included)

YouTube discovery — channel/video search using the official YouTube Data
API v3, official embeds only. Per spec §14: no downloading, no re-hosting,
no scraping of any other social platform.

**Why an Edge Function**: the YouTube API key must never reach the browser
— a client-exposed key can be extracted and abused against your quota
within minutes. So the search call goes through a small server-side proxy:

```
Browser → sb.functions.invoke('youtube-search') → Edge Function (holds the key) → YouTube Data API
```

New file: `supabase/functions/youtube-search/index.ts`

### Setup

1. **Get a YouTube Data API key**: Google Cloud Console → enable "YouTube
   Data API v3" → Credentials → Create API key. Restrict it to that API.
2. **Install the Supabase CLI** if you don't have it: `npm install -g supabase`
3. **Link and deploy**:
   ```
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase functions deploy youtube-search
   supabase secrets set YOUTUBE_API_KEY=your_key_here
   ```
   Your project ref is the subdomain in your Supabase URL
   (`https://<project-ref>.supabase.co`).
4. That's it — the frontend already calls it via `sb.functions.invoke(...)`,
   which uses your existing anon key for auth automatically.

### What it does in the app

A new **YouTube tab**: search videos or channels, thumbnails link out to
the real YouTube page, and tapping a video thumbnail plays it inline using
YouTube's own `<iframe>` embed — never a downloaded file.

### Graceful fallback

If `YOUTUBE_API_KEY` isn't set yet, or the YouTube API errors out (quota,
bad key, etc.), the function returns a clean empty result instead of
crashing, and the tab shows "YouTube discovery isn't available right now"
rather than a broken screen — per spec §45/§55.

## Phase 6 (now included)

Earn Center, referral system, and a demo advertising marketplace. Run
`supabase/schema_phase6.sql` **after** phases 1–4.

- **`platform_settings`** — revenue-share and eligibility numbers
  (`REFERRAL_REWARD_RATE_INR`, `MINIMUM_CREATOR_FOLLOWERS`, etc.) live in
  the database, publicly readable but never writable by the client — per
  spec §20, these are never hard-coded in frontend JS.
- **Referrals are now functional**: signup has an optional referral-code
  field; when a referred user makes their first post, a trigger marks the
  referral "qualified" and credits the referrer a *pending* earning event
  at the configured rate — no fake instant payouts.
- **`earning_events`** — a real ledger, trigger-only writes, readable only
  by its owner. The Earn tab shows total/pending/available plus the full
  event list.
- **Demo ad marketplace**: any user can register as an advertiser and
  launch a campaign (headline, body, target URL, demo budget) for the
  `HOME_FEED_TOP` slot. One active campaign shows at the top of the Home
  feed, clearly marked **Sponsored**, with "Why am I seeing this?", Hide,
  and Report controls per spec §48. Impressions/clicks are logged to
  `ad_events` and rolled up into each campaign's counters automatically.
- **Creator eligibility**: the Earn tab checks the logged-in user's
  followers/posts against the configured minimums and shows a clear ✓ or
  a gap — transparent, not a black box.

This is illustrative infrastructure — no real payment processor or ad
network (Google Ad Manager, etc.) is connected. That's future work once
the platform is ready for it, per spec §16.

## Phase 7 (now included)

Privacy Center, E2E messaging, and moderation. Run
`supabase/schema_phase7.sql` **after** phases 1–4 and 6.

- **Privacy Center** — a real page (footer link, or from Messages) with
  plain-language sections on what's public, what's encrypted, what's not
  stored, and what we don't claim ("legally certified," "100% anonymous" —
  never, per spec §30).
- **E2E messaging is functional**: each user gets an RSA-OAEP keypair
  generated in the browser on first visit to Messages. Sending a message
  generates a fresh AES-GCM key, encrypts the text with it, then wraps that
  AES key twice with RSA (once for the recipient, once for the sender) so
  both sides can read the conversation later. The server (`messages_metadata`)
  only ever stores ciphertext.
  - **Honest limitation, stated plainly in the Privacy Center**: the
    private key lives in browser `localStorage`, not on the server. Switch
    devices or clear browser data without exporting your key first, and
    old messages become unreadable — there's no backend recovery, because
    that's what "the server never sees plaintext" actually means.
- **Moderation**: Report (with a reason) and Block buttons on every post.
  Blocking removes that person's posts/polls from your feed and is checked
  via RLS-backed tables (`blocks`, `reports`). There's no full admin review
  queue yet — reports are visible via the Supabase dashboard for now.
- **Your Data** (Profile tab): download a JSON export of your profile,
  posts, and comments, or delete your public content outright. Full
  account deletion (removing the `auth.users` row) needs a service-role
  call this frontend intentionally doesn't make — that's flagged as a
  "contact support" step rather than faked.

## Phase 8 (now included — final phase)

Responsive, performance, and accessibility polish. No database changes —
`index.html` only.

- **Accessibility**: a skip-to-content link, `role="tablist"`/`aria-selected`
  on the main tabs, `aria-label`s on icon-only buttons (like, comment,
  report, block), `aria-live` regions on inline success/error messages,
  visible focus outlines (`:focus-visible`), and `prefers-reduced-motion`
  is respected (skeleton shimmer and smooth-scroll both turn off).
- **Mobile**: a fixed bottom navigation bar (Home / Groups / Search / Chat
  / Profile) appears under 640px, matching the spec's mobile-first bottom
  nav — the full tab bar remains as a horizontally-scrollable strip above
  it for the tabs that don't fit.
- **Performance**: the Home feed now paginates posts 15 at a time with a
  "Load more" button instead of fetching 30 posts on every load — per spec
  §37 ("do not load 1,000 demo profiles at once, paginate them"), applied
  here to the real feed too.
- Added `<meta name="description">`, `<meta name="theme-color">`, and a
  `preconnect` hint to the Supabase project domain for a faster first
  request.

## Phase 9 — fixes + remaining quick wins (this round)

You asked specifically why message notifications weren't arriving, plus to
finish whatever's left, fastest-impact first. Priority order used, and why:

1. **Message notifications (the reported bug)** — a trigger on
   `messages_metadata` now inserts a `'message'`-type notification for the
   recipient the moment a message is sent. The Alerts tab's unread dot also
   now polls every 25 seconds while you're logged in, so you don't have to
   sit on the Alerts tab to notice — highest priority since it was reported
   as broken.
2. **Save/bookmark posts** — quick, high-visible-value, was in the original
   spec's post actions list. Tap 🔖 on any post; find them later under
   Profile → "Saved Posts".
3. **Demo polls** — the original spec's demo ecosystem included sample
   polls with sample responses; these were missing. ~10 illustrative polls
   now show on the landing page's demo section (static results, not
   interactive — they're DEMO content).
4. **Latest / Trending sort** on the Home feed — a fast, self-contained
   addition (`ORDER BY likes_count` vs `created_at`) that covers part of
   the spec's "Explore → Trending" idea without a bigger rebuild.

Run `supabase/schema_phase9.sql` after phases 1–4, 6, 7. Only `index.html`
changed besides that.

### Deliberately deferred (bigger, lower-ratio-of-value-to-time)

- **Admin review dashboard** — needs a role system (admin flag + RLS
  changes across nearly every table) before it can be built safely. Real
  scope, not a quick add.
- **Full multilingual UI (English/Marathi/Hindi)** — `profiles.language`
  already exists as a column, but translating every UI string and wiring a
  language switcher is a large, mostly-mechanical effort better done as its
  own focused pass rather than squeezed in.
- **Creator Studio analytics (views-over-time charts)** — needs a
  page-view event log that doesn't exist yet; the current channel view
  count is a simple counter, not a time series.
- **Real ad-network / payment integration** — explicitly future work per
  the original spec (§16); nothing to build client-side today.

Say the word on any of these and it's next.

| Area | Status |
|---|---|
| Auth: signup/login/logout/reset | ✅ (reset via Supabase's built-in flow) |
| Social: profile/follow/post/like/comment/save/share | ✅ except "save" (bookmarking) — not built |
| Discovery: search/explore/trending/topics/YouTube | ✅ search + YouTube; no separate trending/topics view |
| Communities: create/join/post/moderate | ✅ create/join/post; no per-community moderator tools yet |
| Creator: channel/analytics/earnings | ✅ channel + Earn Center; no full Creator Studio analytics tabs |
| Monetization: Earn Center/demo revenue/referral/ad slots/eligibility | ✅ |
| Privacy: Privacy Center/data settings/deletion/E2E | ✅ |
| Demo: 1,000 accounts/posts/communities/polls | ✅ accounts+posts+communities; demo polls not seeded |
| Security: RLS/no service-role key/validation/report-block | ✅ |
| Deployment: GitHub + static hosting + mobile responsive | ✅ |

Not built, honestly: admin review dashboard, full multilingual UI (EN/MR/HI
throughout), advertiser payment integration, bookmarking/"save", and a
dedicated Creator Studio analytics view — these are natural next steps
beyond the original 8-phase roadmap.

## Phase 10 — the four remaining big items, now closed out

### 1. Admin dashboard ✅
Run `schema_phase10.sql`, then bootstrap your first admin (nobody gets this
from signup — it's a manual, deliberate step):
```sql
update public.profiles set is_admin = true where username = 'yourusername';
```
Log back in — an **Admin** tab appears (hidden for everyone else): platform
metrics (users/posts/communities/open reports) and a moderation queue
pulling from every filed report. Dismiss or Remove content directly —
removing sets the post/comment/community to REMOVED or suspends a
reported user.

### 2. Marathi + Hindi UI ✅ (primary chrome — not literally every string)
A language switcher (EN / मराठी / हिंदी) sits in the top-right header,
works logged in or out, and persists (localStorage, plus `profiles.language`
for logged-in users). It covers navigation, the landing page, auth forms,
and the most common actions.

**Honest scope**: this translates interface chrome, not user-generated
content (that's what people type) and not every secondary string (error
toasts, less-common labels). Full 100% coverage of every string across all
10 phases would be its own dedicated pass; this covers what a first-time
Marathi/Hindi speaker sees immediately.

### 3. Real ad payments (Razorpay) ✅ scaffolding — needs your own keys
Two new Edge Functions: `create-razorpay-order` (creates the order, pins
the amount server-side) and `verify-razorpay-payment` (checks Razorpay's
HMAC signature server-side before crediting the campaign — this is what
makes it a real payment rather than something the browser could fake). In
the Earn tab, each campaign now has a **"Fund with Razorpay"** button that
opens real Razorpay Checkout.

**This one genuinely needs your own account** — it can't be completed
without your business's Razorpay credentials:
1. Sign up at razorpay.com (test mode needs no KYC and works immediately
   with test cards; live payments need business KYC)
2. Get your Key ID + Key Secret from Settings → API Keys
3. Deploy both functions the same way as `youtube-search` (via the
   dashboard editor)
4. Set secrets: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` — Supabase already
   provides `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` to every Edge
   Function automatically, no need to set those yourself

### 4. Creator Studio analytics chart ✅
The Earn tab now draws a 14-day engagement bar chart (likes + comments
received on your posts, per day) using a plain `<canvas>` — no chart
library needed. It's real data, computed client-side from your actual
`likes` and `comments` tables.

All 10 phases are now built. What's left is real business setup (your own
Razorpay account, an admin username to promote) rather than more code.

## Phase 12 — responsive layout, images, Explore, onboarding

No new database changes — `index.html` only.

- **Responsive across devices**: at ≥1100px width (laptop/desktop) the Home
  feed now shows a two-column layout with a sticky right rail (Trending
  now, Suggested creators) — desktop screen space was sitting unused
  before. At ≥900px (tablet/iPad) content gets a bit more breathing room.
  Below that it's still the single-column, bottom-nav mobile layout from
  Phase 8. No layout is hidden or broken on any of these — it's the same
  HTML, just reflowed by CSS grid at different breakpoints.
- **Image posts (Cloudinary, unsigned upload)** — the composer has an
  image button now; pick a photo, it uploads straight to Cloudinary from
  the browser (no backend needed — that's what an *unsigned* upload preset
  is for) and shows inline in the feed. **Action needed**: replace
  `CLOUDINARY_CLOUD_NAME` and `CLOUDINARY_UPLOAD_PRESET` near the top of
  the `<script>` in `index.html` with your own — sign up at cloudinary.com
  (free tier is generous), then Settings → Upload → Add an **unsigned**
  upload preset.
- **Explore tab** — Popular Creators, New Creators, Trending Posts, Browse
  Communities, all from real data (follower counts, signup dates, likes,
  member counts) — the "Explore" section from the original spec that was
  previously folded into Search only.
- **Onboarding** — after signup, a 3-step flow: pick interests (saved to
  your profile), follow a few suggested creators, join a community. It's
  skippable at any point.

## Phase 13 — the last seven items

Run `supabase/schema_phase12.sql` after phases 1–4, 6, 7, 10, 11. Deploy
the new `ai-assist` Edge Function the same way as the others.

1. **Video & link posts** — composer now has 🎬 (paste a video URL — YouTube
   links embed properly, direct `.mp4` links play in a native player) and
   🔗 (paste any link — renders as a card). No upload pipeline for video
   files themselves; that's a bigger addition (large file handling, storage
   costs) — URL-based covers the common case fast.
2. **Creator Studio tabs** — new **Studio** tab: Overview (stats + badges)
   and Posts (manage/delete your posts, appeal a removed one). Analytics
   and Monetization stay in the Earn tab rather than being duplicated.
3. **Gamification** — five starter badges (First Post, Rising Creator, Top
   Creator, Prolific Poster, Community Builder) computed live from your
   real stats, shown in Studio → Overview. Add more rules in `BADGE_RULES`
   in `index.html` whenever you want.
4. **AI features** — a ✨ **Improve** button in the composer rewrites your
   draft via Claude (through the new `ai-assist` Edge Function). **Needs
   your own Anthropic API key** from console.anthropic.com — separate from
   any Claude.ai subscription, this is a paid API account. Set the
   `ANTHROPIC_API_KEY` secret the same way as the other functions.
5. **Mute** — a 🔕 button next to Report/Block on every post. Unlike Block,
   muting is silent and one-directional: they're hidden from your feed but
   can still message/follow you normally, and they're never told.
6. **Appeal workflow** — a removed post shows "Appeal removal" in Studio →
   Posts; a suspended account shows an appeal button right on the Profile
   tab. Admin tab has a new **Appeals** queue to approve (restores the
   content/account) or deny.
7. **Admin settings UI** — the Admin tab can now edit `platform_settings`
   (referral rate, eligibility thresholds, etc.) and add/remove
   `banned_terms` directly — no more SQL editor required for day-to-day
   moderation tuning.

## What's still genuinely not built
A real video-file upload pipeline (vs. URL-based), Brand Opportunities
matching, and a fully separate Analytics sub-tab in Studio (it currently
points to the existing Earn tab chart instead of duplicating it).

## Phase 14 — launch-readiness essentials

- **Forgot password** — a working link on the login form. Uses Supabase's
  built-in reset-email flow; clicking the emailed link brings the person
  back to the site and shows a "set new password" form automatically.
- **Terms acceptance at signup** — a required checkbox linking to the
  Legal page. Signup is blocked until it's checked — this is the piece
  that was missing for the Terms of Service to mean anything.
- **Favicon** — a small inline one, so the browser tab doesn't look
  unfinished. Replace with a real logo file whenever you have one.

No schema changes, no new secrets — just `index.html`.

## ⭐ Consolidated deployment order (run this once, in this order)

Across 14 phases this has piled up into a lot of files. Here's the actual
order to run everything from scratch on a fresh Supabase project — skip
any step you've already done:

**SQL (Supabase → SQL Editor, run each file's contents in order):**
1. `supabase/schema.sql`
2. `supabase/schema_phase2.sql`
3. `supabase/schema_phase3.sql`
4. `supabase/schema_phase4.sql` (seeds ~1,000 demo accounts — takes a
   minute or two)
5. `supabase/schema_phase6.sql`
6. `supabase/schema_phase7.sql`
7. `supabase/schema_phase9.sql`
8. `supabase/schema_phase10.sql`
9. `supabase/schema_phase11.sql`
10. `supabase/schema_phase12.sql`
11. Bootstrap your admin account:
    ```sql
    update public.profiles set is_admin = true where username = 'yourusername';
    ```

**Edge Functions (Supabase → Edge Functions → Deploy via Editor, paste
each file's code, name it exactly as shown):**
1. `youtube-search`
2. `create-razorpay-order`
3. `verify-razorpay-payment`
4. `ai-assist`

**Secrets (Supabase → Edge Functions → Secrets) — only needed for the
functions you actually want working:**
- `YOUTUBE_API_KEY` — for YouTube tab
- `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET` — for real ad payments
- `ANTHROPIC_API_KEY` — for the AI ✨ Improve button
- (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` are provided automatically —
  never set these yourself)

**Frontend config (edit near the top of `index.html`):**
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` — required, the site won't work
  without these
- `CLOUDINARY_CLOUD_NAME` / `CLOUDINARY_UPLOAD_PRESET` — only needed for
  image posts; everything else works without it

**Then:** push `index.html` to your GitHub repo, confirm GitHub Pages is
serving it, and do one signup → post → like → comment → follow →
message → community → poll pass to confirm the live site behaves the
way it did in testing.

Every one of `YOUTUBE_API_KEY`, `RAZORPAY_KEY_ID`/`SECRET`, and
`ANTHROPIC_API_KEY` is optional — the site degrades gracefully (a plain
"not available right now" message) for any one you skip. Nothing else
depends on them.

## Phase 15 — from the NEXA audit, fastest-value items first

Run `supabase/schema_phase13.sql` after the others (adds one column).
Only `index.html` changed besides that.

Priority was: fix the one real security gap first, then the items from
the audit buildable in minutes rather than days.

1. **XSS hardening on user-supplied URLs** (security, done first) — image/
   video/link posts, and the sponsored ad card, now validate every URL is
   http(s) before rendering it and escape it properly for the attribute
   it's placed in. Previously a crafted URL in a video or link post could
   have broken out of the `src`/`href` attribute; that gap is closed. Also
   applied at the point of entry — pasting a non-http(s) URL into the
   video/link composer buttons is now rejected immediately.
2. **"Why am I seeing this?"** on the Home feed — a button next to
   Latest/Trending that explains the ranking honestly: chronological for
   Latest, like-count for Trending. **No false claims of personalization**
   — the feed doesn't actually personalize yet, so the explanation says
   that plainly rather than inventing signals that aren't real.
3. **Social Value Score** — an illustrative 0–100 score in Studio →
   Overview, computed from real followers/posts/engagement. Explicitly
   labeled as not an earnings figure, per the audit's own requirement
   ("never presented as a guaranteed earning amount").
4. **Social Passport (external links)** — Studio → Overview now has
   YouTube/Instagram/X/Other link fields, validated and saved to your
   profile. **Honest scope**: these are plain links you type in, not
   OAuth-verified connections — there's no "✓ YouTube" badge because that
   would require registering a real OAuth app per platform (a Meta/Google
   developer app + review process, similar to the Razorpay/YouTube setup
   you've already done). Displaying them on a *public* profile-viewing
   page is also not wired up yet, since Nexus doesn't have a separate
   "view someone else's profile" page — only your own Profile/Studio.

## Deliberately not started this round (bigger, lower ratio of value to time)
- **Group chat** — the current E2EE design is 1-to-1 (one AES key wrapped
  for exactly two people). Group chat needs the AES key wrapped for every
  member and rewrapped whenever membership changes — a real redesign, not
  an extension.
- **Business Mode** — a whole parallel profile type (business listings,
  offers, local campaigns) — a multi-phase feature on its own.
- **Full multi-language architecture** (Gujarati/Bengali/Tamil/etc.) —
  the current EN/MR/HI setup would need to become a proper translation-key
  system before adding more languages cheaply; right now each language is
  a hand-written object.
- **Splitting `index.html` into modules** — the file has grown large
  across 15 phases. It still works fine as one file for a GitHub
  Pages-style static site, but a real modular rewrite (separate JS files,
  a build step) is worth doing before the codebase grows much further —
  it's an architecture change, not a feature, so it wasn't the fastest
  win for a launch-focused pass.
