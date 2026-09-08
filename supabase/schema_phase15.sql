-- ============================================================
-- NEXUS — Phase 15 Schema
-- Public profile views, Business Mode, group chat (fixed-membership).
-- Run AFTER phases 1–4, 6, 7, 10, 11, 12, 13, 14.
-- ============================================================

-- ------------------------------------------------------------
-- PROFILE VIEW COUNTER
-- profiles.channel_views_count already exists but nothing wrote
-- to it (no public profile page existed). This RPC lets the new
-- public profile page increment it — callable by anyone, including
-- signed-out visitors, since view counts aren't sensitive, but it
-- can only ever increment by exactly 1 and can't touch anything
-- else on the row.
-- ------------------------------------------------------------
create or replace function public.increment_profile_view(target_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set channel_views_count = channel_views_count + 1 where id = target_id;
end;
$$;
grant execute on function public.increment_profile_view(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- BUSINESS MODE
-- A profile can flip on a business identity and list products,
-- services, or offers. Kept modular per spec §20 — off by default,
-- doesn't change anything about a normal creator profile.
-- ------------------------------------------------------------
alter table public.profiles add column if not exists is_business boolean not null default false;
alter table public.profiles add column if not exists business_category text;
alter table public.profiles add column if not exists business_description text;

create table if not exists public.business_listings (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 120),
  description text not null default '',
  listing_type text not null default 'product' check (listing_type in ('product','service','offer')),
  price_inr integer,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','REMOVED')),
  created_at timestamptz not null default now()
);
create index if not exists business_listings_business_idx on public.business_listings (business_id);

alter table public.business_listings enable row level security;
drop policy if exists "listings publicly readable" on public.business_listings;
create policy "listings publicly readable" on public.business_listings for select using (status = 'ACTIVE');
drop policy if exists "owner manages own listings" on public.business_listings;
create policy "owner manages own listings" on public.business_listings for insert with check (auth.uid() = business_id);
drop policy if exists "owner updates own listings" on public.business_listings;
create policy "owner updates own listings" on public.business_listings for update using (auth.uid() = business_id);
drop policy if exists "owner deletes own listings" on public.business_listings;
create policy "owner deletes own listings" on public.business_listings for delete using (auth.uid() = business_id);

-- ------------------------------------------------------------
-- GROUP CHAT (E2EE, fixed membership — v1)
--
-- Honest scope: membership is set ONCE at creation time by the
-- creator. There is no "add member later" in this version,
-- because doing that properly requires an existing member's
-- browser to be online to re-wrap the group's AES key for the
-- new person — a real feature, just not this one. Start a new
-- group if you need different membership.
--
-- One AES-256 key per group, generated client-side, wrapped with
-- each member's RSA public key (same wrap/unwrap pattern as the
-- existing 1-to-1 messages_metadata). The server only ever stores
-- ciphertext + wrapped keys, never a usable key or plaintext.
-- ------------------------------------------------------------
create table if not exists public.chat_groups (
  id uuid primary key default uuid_generate_v4(),
  name text not null check (char_length(name) between 1 and 80),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_group_members (
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  wrapped_key text not null, -- the group's AES key, RSA-wrapped for this member
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.group_messages (
  id uuid primary key default uuid_generate_v4(),
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  ciphertext text not null,
  iv text not null,
  created_at timestamptz not null default now()
);
create index if not exists group_messages_group_idx on public.group_messages (group_id, created_at);

alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.group_messages enable row level security;

drop policy if exists "members read their groups" on public.chat_groups;
create policy "members read their groups"
  on public.chat_groups for select
  using (exists (select 1 from public.chat_group_members m where m.group_id = id and m.user_id = auth.uid()));
drop policy if exists "creator makes a group" on public.chat_groups;
create policy "creator makes a group"
  on public.chat_groups for insert
  with check (auth.uid() = creator_id);

drop policy if exists "members read membership" on public.chat_group_members;
create policy "members read membership"
  on public.chat_group_members for select
  using (exists (select 1 from public.chat_group_members m2 where m2.group_id = group_id and m2.user_id = auth.uid()));
drop policy if exists "creator adds initial members" on public.chat_group_members;
create policy "creator adds initial members"
  on public.chat_group_members for insert
  with check (exists (select 1 from public.chat_groups g where g.id = group_id and g.creator_id = auth.uid()));

drop policy if exists "members read group messages" on public.group_messages;
create policy "members read group messages"
  on public.group_messages for select
  using (exists (select 1 from public.chat_group_members m where m.group_id = group_id and m.user_id = auth.uid()));
drop policy if exists "members send group messages" on public.group_messages;
create policy "members send group messages"
  on public.group_messages for insert
  with check (
    auth.uid() = sender_id
    and exists (select 1 from public.chat_group_members m where m.group_id = group_id and m.user_id = auth.uid())
  );
