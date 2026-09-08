-- ============================================================
-- NEXUS — Phase 14 Schema
-- @mentions, community rules, article post type.
-- Run AFTER phases 1–4, 6, 7, 10, 11, 12, 13.
-- ============================================================

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('follow','like','comment','community_join','poll_vote','message','mention'));

alter table public.posts drop constraint if exists posts_post_type_check;
alter table public.posts add constraint posts_post_type_check
  check (post_type in ('text','image','video','link','poll','question','article'));

alter table public.communities add column if not exists rules text not null default '';

-- ------------------------------------------------------------
-- @MENTIONS — scan new posts/comments for @username and notify
-- each mentioned user who actually exists. Simple regex match,
-- not a full-text index — fine at this scale.
-- ------------------------------------------------------------
create or replace function public.notify_on_mentions()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_username text;
  v_target_id uuid;
  v_actor_id uuid;
begin
  v_actor_id := case when TG_TABLE_NAME = 'posts' then new.author_id else new.author_id end;
  for v_username in
    select distinct lower(m[1]) from regexp_matches(new.content, '@([a-zA-Z0-9_]{2,30})', 'g') as m
  loop
    select id into v_target_id from public.profiles where lower(username) = v_username;
    if v_target_id is not null and v_target_id <> v_actor_id then
      insert into public.notifications (user_id, actor_id, type, post_id)
      values (v_target_id, v_actor_id, 'mention', case when TG_TABLE_NAME = 'posts' then new.id else new.post_id end);
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists posts_notify_mentions on public.posts;
create trigger posts_notify_mentions after insert on public.posts
  for each row execute function public.notify_on_mentions();

drop trigger if exists comments_notify_mentions on public.comments;
create trigger comments_notify_mentions after insert on public.comments
  for each row execute function public.notify_on_mentions();
