-- ============================================================
-- NEXUS — Phase 1 Schema
-- Foundation: profiles + auth wiring
-- Run this in the Supabase SQL editor (or via `supabase db push`)
-- Later phases (posts, follows, communities, earnings, ads...)
-- will each ship as their own numbered migration file.
-- ============================================================

create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- PROFILES
-- One row per auth.users row. Created automatically on signup
-- via the trigger below — the client never inserts this table
-- directly except to update its own row.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null default '',
  bio text not null default '',
  avatar_url text,
  location text,
  interests text[] not null default '{}',
  language text not null default 'en' check (language in ('en','mr','hi')),

  -- every user automatically gets a creator-style channel (spec §8)
  channel_name text not null default '',
  channel_followers_count integer not null default 0,
  channel_posts_count integer not null default 0,
  channel_views_count integer not null default 0,

  referral_code text unique not null default upper(substr(replace(uuid_generate_v4()::text,'-',''),1,8)),
  referred_by uuid references public.profiles(id),

  is_demo boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','REPORTED','UNDER_REVIEW','REMOVED','SUSPENDED')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_username_idx on public.profiles (username);
create index if not exists profiles_is_demo_idx on public.profiles (is_demo);

-- keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- Auto-create a profile row whenever a new auth user signs up.
-- Username defaults to part of the email; the user renames it
-- during onboarding.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  base_username text;
  final_username text;
  suffix int := 0;
begin
  base_username := lower(regexp_replace(split_part(new.email, '@', 1), '[^a-z0-9_]', '', 'g'));
  if base_username = '' then
    base_username := 'user';
  end if;
  final_username := base_username;

  while exists (select 1 from public.profiles where username = final_username) loop
    suffix := suffix + 1;
    final_username := base_username || suffix::text;
  end loop;

  insert into public.profiles (id, username, display_name, channel_name)
  values (new.id, final_username, coalesce(new.raw_user_meta_data->>'display_name', base_username), coalesce(new.raw_user_meta_data->>'display_name', base_username) || '''s Channel');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

-- anyone (incl. anon) can view active, non-suspended profiles —
-- this is a public social platform, profiles are public by design
drop policy if exists "profiles are publicly readable" on public.profiles;
create policy "profiles are publicly readable"
  on public.profiles for select
  using (status in ('ACTIVE','REPORTED','UNDER_REVIEW'));

-- a user may only update their own row, and may never change
-- fields that must stay server/trigger-controlled
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- no direct client inserts — rows are created only by the
-- handle_new_user() trigger (security definer)
drop policy if exists "no direct inserts" on public.profiles;
create policy "no direct inserts"
  on public.profiles for insert
  with check (false);
