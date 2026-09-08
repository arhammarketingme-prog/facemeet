-- ============================================================
-- NEXUS — Phase 6 Schema
-- Earn Center, referrals, demo ad marketplace/advertising
-- architecture. Run AFTER phases 1–4 (phase 5 has no DB changes).
-- ============================================================

-- ------------------------------------------------------------
-- PLATFORM SETTINGS
-- Revenue-share and eligibility numbers live here, NOT hard-coded
-- in frontend JS (spec §20). Public read so the Earn Center can
-- show real numbers; no client write policy exists at all, so
-- only this SQL editor (table owner) can change them.
-- ------------------------------------------------------------
create table if not exists public.platform_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into public.platform_settings (key, value) values
  ('PLATFORM_REVENUE_SHARE', '70'),
  ('CREATOR_REVENUE_SHARE', '30'),
  ('REFERRAL_REWARD_RATE_INR', '50'),
  ('MINIMUM_PAYOUT_INR', '500'),
  ('MINIMUM_CREATOR_FOLLOWERS', '50'),
  ('MINIMUM_CREATOR_POSTS', '5')
on conflict (key) do nothing;

alter table public.platform_settings enable row level security;
drop policy if exists "settings publicly readable" on public.platform_settings;
create policy "settings publicly readable" on public.platform_settings for select using (true);
-- intentionally no insert/update/delete policy — the client can never write here

-- ------------------------------------------------------------
-- REFERRALS
-- One row per referred user. Only ever written by triggers
-- (handle_new_user on signup, check_referral_qualification on
-- that user's first post) — never directly by the client.
-- ------------------------------------------------------------
create table if not exists public.referrals (
  referred_id uuid primary key references public.profiles(id) on delete cascade,
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','qualified')),
  created_at timestamptz not null default now()
);
create index if not exists referrals_referrer_idx on public.referrals (referrer_id);

alter table public.referrals enable row level security;
drop policy if exists "users read own referrals" on public.referrals;
create policy "users read own referrals"
  on public.referrals for select
  using (auth.uid() = referrer_id or auth.uid() = referred_id);
-- no insert/update policy — trigger-only via security definer functions

-- ------------------------------------------------------------
-- EARNING EVENTS (the ledger)
-- Trigger-only inserts, same reasoning as notifications.
-- ------------------------------------------------------------
create table if not exists public.earning_events (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('referral_reward','ad_revenue','creator_reward','affiliate','campaign_earning')),
  amount_inr integer not null default 0,
  status text not null default 'pending' check (status in ('pending','available','paid')),
  note text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists earning_events_user_idx on public.earning_events (user_id, created_at desc);

alter table public.earning_events enable row level security;
drop policy if exists "users read own earnings" on public.earning_events;
create policy "users read own earnings"
  on public.earning_events for select
  using (auth.uid() = user_id);
-- no insert/update policy — trigger-only

-- ------------------------------------------------------------
-- ADVERTISERS + AD CAMPAIGNS (demo ad marketplace, spec §16/§47/§48)
-- Any user can register as an advertiser and create demo
-- campaigns — this is illustrative infrastructure, not a real
-- payment-backed ad network (that's a later integration with
-- Google Ad Manager or similar, per spec §16).
-- ------------------------------------------------------------
create table if not exists public.advertisers (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  company_name text not null check (char_length(company_name) between 2 and 100),
  created_at timestamptz not null default now()
);

alter table public.advertisers enable row level security;
drop policy if exists "advertisers publicly readable" on public.advertisers;
create policy "advertisers publicly readable" on public.advertisers for select using (true);
drop policy if exists "users register as advertiser" on public.advertisers;
create policy "users register as advertiser" on public.advertisers for insert with check (auth.uid() = user_id);

create table if not exists public.ad_campaigns (
  id uuid primary key default uuid_generate_v4(),
  advertiser_id uuid not null references public.advertisers(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 100),
  slot text not null default 'HOME_FEED_TOP' check (slot in
    ('HOME_FEED_TOP','HOME_FEED_NATIVE','EXPLORE_CARD','COMMUNITY','CREATOR_PAGE','VIDEO_SECTION')),
  headline text not null check (char_length(headline) between 3 and 120),
  body text not null default '',
  target_url text not null,
  budget_inr integer not null default 0,
  status text not null default 'active' check (status in ('draft','active','paused','ended')),
  impressions_count integer not null default 0,
  clicks_count integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists ad_campaigns_slot_idx on public.ad_campaigns (slot, status);

alter table public.ad_campaigns enable row level security;
drop policy if exists "active campaigns publicly readable" on public.ad_campaigns;
create policy "active campaigns publicly readable"
  on public.ad_campaigns for select
  using (status = 'active' or exists (select 1 from public.advertisers a where a.id = advertiser_id and a.user_id = auth.uid()));

drop policy if exists "advertiser creates own campaign" on public.ad_campaigns;
create policy "advertiser creates own campaign"
  on public.ad_campaigns for insert
  with check (exists (select 1 from public.advertisers a where a.id = advertiser_id and a.user_id = auth.uid()));

drop policy if exists "advertiser updates own campaign" on public.ad_campaigns;
create policy "advertiser updates own campaign"
  on public.ad_campaigns for update
  using (exists (select 1 from public.advertisers a where a.id = advertiser_id and a.user_id = auth.uid()));

-- AD EVENTS: impressions/clicks. Anyone (incl. anon) may log one —
-- this is what "valid impressions/clicks" get counted from
-- (spec §16) — but they can never be read back by the client,
-- only aggregated into ad_campaigns' counters by the trigger.
create table if not exists public.ad_events (
  id uuid primary key default uuid_generate_v4(),
  campaign_id uuid not null references public.ad_campaigns(id) on delete cascade,
  event_type text not null check (event_type in ('impression','click')),
  user_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.ad_events enable row level security;
drop policy if exists "anyone logs ad events" on public.ad_events;
create policy "anyone logs ad events" on public.ad_events for insert with check (true);
-- no select policy — event log isn't directly readable by clients

create or replace function public.on_ad_event_insert()
returns trigger language plpgsql as $$
begin
  if new.event_type = 'impression' then
    update public.ad_campaigns set impressions_count = impressions_count + 1 where id = new.campaign_id;
  elsif new.event_type = 'click' then
    update public.ad_campaigns set clicks_count = clicks_count + 1 where id = new.campaign_id;
  end if;
  return new;
end;
$$;
drop trigger if exists ad_events_after_insert on public.ad_events;
create trigger ad_events_after_insert after insert on public.ad_events
  for each row execute function public.on_ad_event_insert();

-- ------------------------------------------------------------
-- REFERRAL WIRING
-- 1. Extend signup to accept a referral code and record it.
-- 2. When a referred user creates their FIRST post, mark the
--    referral qualified and credit the referrer a pending
--    earning event, using the configured rate — never a
--    hard-coded number.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  base_username text;
  final_username text;
  suffix int := 0;
  v_referrer_id uuid;
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

  -- look up a referrer from the code the new user typed in, if any
  if new.raw_user_meta_data ? 'referral_code' and length(new.raw_user_meta_data->>'referral_code') > 0 then
    select id into v_referrer_id from public.profiles where referral_code = upper(trim(new.raw_user_meta_data->>'referral_code'));
  end if;

  insert into public.profiles (id, username, display_name, channel_name, referred_by)
  values (
    new.id, final_username,
    coalesce(new.raw_user_meta_data->>'display_name', base_username),
    coalesce(new.raw_user_meta_data->>'display_name', base_username) || '''s Channel',
    v_referrer_id
  );

  if v_referrer_id is not null and v_referrer_id <> new.id then
    insert into public.referrals (referred_id, referrer_id) values (new.id, v_referrer_id)
    on conflict (referred_id) do nothing;
  end if;

  return new;
end;
$$;
-- trigger already exists from Phase 1 and points at this function name, no change needed there

create or replace function public.check_referral_qualification()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_post_count int;
  v_ref record;
  v_rate int;
begin
  select count(*) into v_post_count from public.posts where author_id = new.author_id;
  if v_post_count <> 1 then
    return new; -- only fires on the author's first-ever post
  end if;

  select * into v_ref from public.referrals where referred_id = new.author_id and status = 'pending';
  if v_ref.referred_id is null then
    return new;
  end if;

  update public.referrals set status = 'qualified' where referred_id = new.author_id;

  select coalesce(value::int, 0) into v_rate from public.platform_settings where key = 'REFERRAL_REWARD_RATE_INR';
  insert into public.earning_events (user_id, type, amount_inr, status, note)
  values (v_ref.referrer_id, 'referral_reward', coalesce(v_rate, 0), 'pending', 'Referral bonus — a creator you invited made their first post.');

  return new;
end;
$$;
drop trigger if exists posts_referral_check on public.posts;
create trigger posts_referral_check after insert on public.posts
  for each row execute function public.check_referral_qualification();
