-- ============================================================
-- NEXUS — Phase 11 Schema
-- Automatic content flagging + basic anti-spam rate limiting.
-- Run AFTER phases 1–4, 6, 7, 10.
-- ============================================================

-- ------------------------------------------------------------
-- BANNED TERMS (admin-managed list, publicly unreadable)
-- Deliberately simple keyword matching — this catches obvious,
-- named cases automatically. It is NOT a substitute for a real
-- trust & safety pipeline (see the honest limitations note in
-- the chat reply).
-- ------------------------------------------------------------
create table if not exists public.banned_terms (
  term text primary key
);
alter table public.banned_terms enable row level security;
-- no select/insert/update/delete policy for any client role —
-- admins manage this table via the SQL editor only, and the
-- trigger function below reads it as SECURITY DEFINER

insert into public.banned_terms (term) values
  ('kill yourself'), ('child porn'), ('buy followers cheap'), ('click here to win')
on conflict do nothing;
-- starter list only — add real terms for your context via the SQL editor

-- ------------------------------------------------------------
-- AUTO-FLAG posts/comments containing a banned term, or posted
-- in a spam burst, instead of publishing them immediately.
-- Flagged content gets status = 'UNDER_REVIEW': RLS still lets
-- the author and admins see it, but the app's own feed queries
-- filter to status = 'ACTIVE' only, so it's invisible to
-- everyone else until an admin approves or removes it.
-- ------------------------------------------------------------
create or replace function public.auto_moderate_content()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_hit boolean;
  v_recent_count int;
begin
  select exists (
    select 1 from public.banned_terms b where new.content ilike '%' || b.term || '%'
  ) into v_hit;

  if v_hit then
    new.status := 'UNDER_REVIEW';
    return new;
  end if;

  -- basic spam throttle: more than 8 posts/comments from the same
  -- author in the last 10 minutes gets auto-flagged for review
  if TG_TABLE_NAME = 'posts' then
    select count(*) into v_recent_count from public.posts
      where author_id = new.author_id and created_at > now() - interval '10 minutes';
  else
    select count(*) into v_recent_count from public.comments
      where author_id = new.author_id and created_at > now() - interval '10 minutes';
  end if;

  if v_recent_count >= 8 then
    new.status := 'UNDER_REVIEW';
  end if;

  return new;
end;
$$;

drop trigger if exists posts_auto_moderate on public.posts;
create trigger posts_auto_moderate before insert on public.posts
  for each row execute function public.auto_moderate_content();

drop trigger if exists comments_auto_moderate on public.comments;
create trigger comments_auto_moderate before insert on public.comments
  for each row execute function public.auto_moderate_content();
