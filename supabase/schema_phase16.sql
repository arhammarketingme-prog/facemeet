-- ============================================================
-- NEXUS — Phase 16 Schema — SECURITY FIX (self-audit, unprompted)
--
-- THE BUG: "users update own profile" (and similar policies on
-- ad_campaigns/communities) check WHICH ROW can be updated, but
-- Postgres RLS does not restrict WHICH COLUMNS can be changed in
-- that row. Any signed-in user could therefore call, e.g.:
--   supabase.from('profiles').update({ is_admin: true }).eq('id', me)
-- directly from the browser console and it would succeed — RLS
-- only checked "is this my own row?", not "am I allowed to touch
-- is_admin?". Same risk applied to account status (a suspended
-- user un-suspending themselves), follower/post counts (which
-- feed creator-eligibility and the Social Value Score), and an
-- advertiser inflating their own campaign's budget_inr without
-- actually paying via Razorpay.
--
-- This directly contradicts a rule already stated back in the
-- Phase 10 admin schema and the original spec: "never trust
-- frontend values for earnings, roles, admin privileges,
-- verification — these must be server-validated." The RLS row
-- check alone wasn't enough; column-level protection was missing.
--
-- THE FIX: BEFORE UPDATE triggers that silently revert protected
-- columns to their old value unless the caller is an admin, or
-- the write is a legitimate system-triggered one (flagged via a
-- transaction-local setting the relevant trigger functions set
-- just before they write).
--
-- Run AFTER phases 1–4, 6, 7, 10, 11, 12, 13, 14, 15.
-- ============================================================

create or replace function public.is_system_write()
returns boolean language sql stable as $$
  select coalesce(current_setting('nexus.system_write', true), 'false') = 'true';
$$;

-- ------------------------------------------------------------
-- PROFILES: lock is_admin, status, the channel_* counters,
-- referral_code, referred_by, and username against direct
-- client writes. Everything else you can legitimately edit
-- yourself (bio, channel_name, avatar_url, social_links,
-- is_business, business_*, language, interests) is untouched.
-- ------------------------------------------------------------
create or replace function public.guard_profile_columns()
returns trigger language plpgsql as $$
begin
  if not public.is_admin(auth.uid()) and not public.is_system_write() then
    new.is_admin := old.is_admin;
    new.status := old.status;
    new.channel_followers_count := old.channel_followers_count;
    new.channel_posts_count := old.channel_posts_count;
    new.channel_views_count := old.channel_views_count;
    new.referral_code := old.referral_code;
    new.referred_by := old.referred_by;
    new.username := old.username;
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_guard_columns on public.profiles;
create trigger profiles_guard_columns before update on public.profiles
  for each row execute function public.guard_profile_columns();

-- mark the legitimate system paths that update those counters so
-- the guard above lets them through
create or replace function public.on_post_insert()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_posts_count = channel_posts_count + 1 where id = new.author_id;
  return new;
end;
$$;

create or replace function public.on_post_delete()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_posts_count = greatest(channel_posts_count - 1, 0) where id = old.author_id;
  return old;
end;
$$;

create or replace function public.on_follow_insert()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_followers_count = channel_followers_count + 1 where id = new.following_id;
  return new;
end;
$$;

create or replace function public.on_follow_delete()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_followers_count = greatest(channel_followers_count - 1, 0) where id = old.following_id;
  return old;
end;
$$;

create or replace function public.increment_profile_view(target_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_views_count = channel_views_count + 1 where id = target_id;
end;
$$;
grant execute on function public.increment_profile_view(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- AD_CAMPAIGNS: lock budget_inr against the advertiser directly
-- editing their own campaign's budget. It can only ever change
-- via the verify-razorpay-payment Edge Function, which runs with
-- the service-role key (no user JWT, so auth.uid() is null there)
-- — a real payment must clear Razorpay's signature check first.
-- impressions_count/clicks_count are left as before: they're
-- plain analytics counters with no monetary or access-control
-- weight, so guarding them wasn't worth the added complexity.
-- ------------------------------------------------------------
create or replace function public.guard_campaign_budget()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and not public.is_admin(auth.uid()) then
    new.budget_inr := old.budget_inr;
  end if;
  return new;
end;
$$;
drop trigger if exists ad_campaigns_guard_budget on public.ad_campaigns;
create trigger ad_campaigns_guard_budget before update on public.ad_campaigns
  for each row execute function public.guard_campaign_budget();

-- ------------------------------------------------------------
-- COMMUNITIES: lock members_count and status against the
-- creator directly editing them (e.g. reviving a community an
-- admin removed, or inflating its member count for visibility).
-- ------------------------------------------------------------
create or replace function public.guard_community_columns()
returns trigger language plpgsql as $$
begin
  if not public.is_admin(auth.uid()) and not public.is_system_write() then
    new.members_count := old.members_count;
    new.status := old.status;
  end if;
  return new;
end;
$$;
drop trigger if exists communities_guard_columns on public.communities;
create trigger communities_guard_columns before update on public.communities
  for each row execute function public.guard_community_columns();

create or replace function public.on_community_member_insert()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.communities set members_count = members_count + 1 where id = new.community_id;
  return new;
end;
$$;

create or replace function public.on_community_member_delete()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.communities set members_count = greatest(members_count - 1, 0) where id = old.community_id;
  return old;
end;
$$;
