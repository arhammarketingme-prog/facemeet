-- ============================================================
-- NEXUS — Phase 18 Schema — CRITICAL FUNCTIONAL FIX (self-audit)
--
-- THE BUG: every counter-maintenance trigger function in this
-- project (on_post_insert, on_like_insert/delete, on_comment_
-- insert/delete, on_follow_insert/delete, on_community_member_
-- insert/delete, on_poll_vote_insert, on_ad_event_insert) was
-- written as a plain PL/pgSQL function — SECURITY INVOKER by
-- default, not SECURITY DEFINER. That means each one's internal
-- UPDATE statement runs with the CALLING USER's own RLS
-- permissions, not elevated ones.
--
-- Concretely: when User B likes User A's post, on_like_insert
-- tries `update posts set likes_count = likes_count + 1 where
-- id = ...`. The posts table's UPDATE policy ("users update own
-- posts") only allows auth.uid() = author_id. User B is not the
-- author, so that predicate fails — Postgres RLS doesn't error,
-- it just silently matches zero rows. The like itself gets
-- recorded (the likes table's own INSERT policy is fine), but
-- the post's likes_count never actually increments.
--
-- The same silent failure applies to: comments_count, follower
-- counts, community members_count, and ad impressions/clicks —
-- ANY time the action is taken by someone other than the row's
-- owner. Poll votes were worse still: poll_options never had
-- an UPDATE policy for anyone at all, so votes_count has never
-- incremented for ANY voter, including a poll's own author.
--
-- This has been silently broken since Phase 2/3/6 — before the
-- Phase 16/17 security guards existed. Those guards added
-- `perform set_config('nexus.system_write', ...)` calls to several
-- of these same functions but did NOT mark them SECURITY DEFINER,
-- so the underlying RLS block was never actually fixed by them —
-- the guard triggers were correct, but the writes they were meant
-- to let through still couldn't reach the row's owner-restricted
-- UPDATE policy in the first place.
--
-- THE FIX: redefine every one of these as SECURITY DEFINER with
-- a pinned search_path (the standard, safe pattern already used
-- correctly elsewhere in this project for notify_on_follow,
-- notify_on_like, handle_new_user, etc.) — combined with the
-- existing nexus.system_write flag so the Phase 16/17 guard
-- triggers still let these specific, legitimate writes through.
--
-- Run AFTER phase 17.
-- ============================================================

create or replace function public.on_post_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_posts_count = channel_posts_count + 1 where id = new.author_id;
  return new;
end;
$$;

create or replace function public.on_post_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_posts_count = greatest(channel_posts_count - 1, 0) where id = old.author_id;
  return old;
end;
$$;

create or replace function public.on_like_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  return new;
end;
$$;

create or replace function public.on_like_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;

create or replace function public.on_comment_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  return new;
end;
$$;

create or replace function public.on_comment_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;

create or replace function public.on_follow_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_followers_count = channel_followers_count + 1 where id = new.following_id;
  return new;
end;
$$;

create or replace function public.on_follow_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_followers_count = greatest(channel_followers_count - 1, 0) where id = old.following_id;
  return old;
end;
$$;

create or replace function public.on_community_member_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.communities set members_count = members_count + 1 where id = new.community_id;
  return new;
end;
$$;

create or replace function public.on_community_member_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.communities set members_count = greatest(members_count - 1, 0) where id = old.community_id;
  return old;
end;
$$;

create or replace function public.on_poll_vote_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.poll_options set votes_count = votes_count + 1 where id = new.option_id;
  return new;
end;
$$;

create or replace function public.on_ad_event_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.event_type = 'impression' then
    update public.ad_campaigns set impressions_count = impressions_count + 1 where id = new.campaign_id;
  elsif new.event_type = 'click' then
    update public.ad_campaigns set clicks_count = clicks_count + 1 where id = new.campaign_id;
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------
-- BACKFILL: recompute every counter this bug could have thrown
-- off, from the actual underlying rows, so existing data is
-- corrected retroactively rather than only fixed going forward.
-- Safe to run more than once.
--
-- (This flags the write as trusted so the Phase 16/17 guard
-- triggers on posts/profiles/communities don't block it — those
-- guards check the request's auth context, and a SQL-editor
-- session has none, so without this they'd otherwise revert
-- these corrections right back to their old, wrong values.)
-- ------------------------------------------------------------
select set_config('nexus.system_write', 'true', true);

update public.posts p set likes_count = (select count(*) from public.likes l where l.post_id = p.id);
update public.posts p set comments_count = (select count(*) from public.comments c where c.post_id = p.id and c.status = 'ACTIVE');
update public.profiles pr set channel_posts_count = (select count(*) from public.posts p where p.author_id = pr.id and p.status = 'ACTIVE');
update public.profiles pr set channel_followers_count = (select count(*) from public.follows f where f.following_id = pr.id);
update public.communities co set members_count = (select count(*) from public.community_members cm where cm.community_id = co.id);
update public.poll_options po set votes_count = (select count(*) from public.poll_votes pv where pv.option_id = po.id);
update public.ad_campaigns ac set
  impressions_count = (select count(*) from public.ad_events ae where ae.campaign_id = ac.id and ae.event_type = 'impression'),
  clicks_count = (select count(*) from public.ad_events ae where ae.campaign_id = ac.id and ae.event_type = 'click');
