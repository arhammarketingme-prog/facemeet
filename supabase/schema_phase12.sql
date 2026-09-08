-- ============================================================
-- NEXUS — Phase 12 Schema
-- Mute, appeal workflow, admin-editable settings, video posts.
-- Run AFTER phases 1–4, 6, 7, 10, 11.
-- ============================================================

-- allow 'video' as a post type (was missing from the original check)
alter table public.posts drop constraint if exists posts_post_type_check;
alter table public.posts add constraint posts_post_type_check
  check (post_type in ('text','image','video','link','poll','question'));

-- ------------------------------------------------------------
-- MUTES — distinct from blocks: a muted person's posts are
-- hidden from your feed, but unlike a block they can still
-- message you, follow you, and see your content normally. They
-- are never told they've been muted.
-- ------------------------------------------------------------
create table if not exists public.mutes (
  muter_id uuid not null references public.profiles(id) on delete cascade,
  muted_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  constraint no_self_mute check (muter_id <> muted_id)
);
alter table public.mutes enable row level security;
drop policy if exists "users read own mutes" on public.mutes;
create policy "users read own mutes" on public.mutes for select using (auth.uid() = muter_id);
drop policy if exists "users create own mutes" on public.mutes;
create policy "users create own mutes" on public.mutes for insert with check (auth.uid() = muter_id);
drop policy if exists "users remove own mutes" on public.mutes;
create policy "users remove own mutes" on public.mutes for delete using (auth.uid() = muter_id);

-- ------------------------------------------------------------
-- APPEALS — for content that was removed or an account that was
-- suspended. A user can appeal their OWN affected content/account;
-- an admin reviews and can restore it.
-- ------------------------------------------------------------
create table if not exists public.appeals (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post','comment','community','account')),
  target_id uuid, -- null when target_type = 'account' (the account itself is user_id)
  message text not null check (char_length(message) between 5 and 1000),
  status text not null default 'pending' check (status in ('pending','approved','denied')),
  created_at timestamptz not null default now()
);
create index if not exists appeals_status_idx on public.appeals (status, created_at desc);

alter table public.appeals enable row level security;
drop policy if exists "users read own appeals" on public.appeals;
create policy "users read own appeals"
  on public.appeals for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));
drop policy if exists "users file own appeals" on public.appeals;
create policy "users file own appeals"
  on public.appeals for insert
  with check (auth.uid() = user_id);
drop policy if exists "admins update appeals" on public.appeals;
create policy "admins update appeals"
  on public.appeals for update
  using (public.is_admin(auth.uid()));

-- a suspended user must still be able to read their OWN profile row
-- (the public-read policy excludes SUSPENDED) so they can see the
-- suspension notice and file an appeal
drop policy if exists "users read own profile regardless of status" on public.profiles;
create policy "users read own profile regardless of status"
  on public.profiles for select
  using (auth.uid() = id);

-- ------------------------------------------------------------
-- ADMIN-EDITABLE SETTINGS + BANNED TERMS
-- Previously these were SQL-editor-only. Now admins can manage
-- them from the Admin tab too.
-- ------------------------------------------------------------
drop policy if exists "admins update settings" on public.platform_settings;
create policy "admins update settings"
  on public.platform_settings for update
  using (public.is_admin(auth.uid()));

drop policy if exists "admins read banned terms" on public.banned_terms;
create policy "admins read banned terms"
  on public.banned_terms for select
  using (public.is_admin(auth.uid()));
drop policy if exists "admins insert banned terms" on public.banned_terms;
create policy "admins insert banned terms"
  on public.banned_terms for insert
  with check (public.is_admin(auth.uid()));
drop policy if exists "admins delete banned terms" on public.banned_terms;
create policy "admins delete banned terms"
  on public.banned_terms for delete
  using (public.is_admin(auth.uid()));
