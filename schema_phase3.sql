-- ============================================================
-- NEXUS — Phase 3 Schema
-- Communities, polls, notifications
-- Run AFTER schema.sql and schema_phase2.sql
-- ============================================================

-- ------------------------------------------------------------
-- COMMUNITIES
-- ------------------------------------------------------------
create table if not exists public.communities (
  id uuid primary key default uuid_generate_v4(),
  slug text unique not null,
  name text not null check (char_length(name) between 2 and 80),
  description text not null default '',
  creator_id uuid not null references public.profiles(id) on delete cascade,
  members_count integer not null default 0,
  is_demo boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','UNDER_REVIEW','REMOVED')),
  created_at timestamptz not null default now()
);
create index if not exists communities_slug_idx on public.communities (slug);

create table if not exists public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('member','moderator','admin')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);
create index if not exists community_members_user_idx on public.community_members (user_id);

-- posts can optionally belong to a community
alter table public.posts add column if not exists community_id uuid references public.communities(id) on delete set null;
create index if not exists posts_community_idx on public.posts (community_id);

-- ------------------------------------------------------------
-- POLLS
-- ------------------------------------------------------------
create table if not exists public.polls (
  id uuid primary key default uuid_generate_v4(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  community_id uuid references public.communities(id) on delete set null,
  question text not null check (char_length(question) between 3 and 300),
  is_demo boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','REMOVED')),
  created_at timestamptz not null default now()
);

create table if not exists public.poll_options (
  id uuid primary key default uuid_generate_v4(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_text text not null check (char_length(option_text) between 1 and 120),
  votes_count integer not null default 0,
  position integer not null default 0
);
create index if not exists poll_options_poll_idx on public.poll_options (poll_id);

create table if not exists public.poll_votes (
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

-- ------------------------------------------------------------
-- NOTIFICATIONS
-- ------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null check (type in ('follow','like','comment','community_join','poll_vote')),
  post_id uuid references public.posts(id) on delete cascade,
  community_id uuid references public.communities(id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

-- ------------------------------------------------------------
-- COUNTER + NOTIFICATION TRIGGERS
-- ------------------------------------------------------------
create or replace function public.on_community_member_insert()
returns trigger language plpgsql as $$
begin
  update public.communities set members_count = members_count + 1 where id = new.community_id;
  return new;
end;
$$;
drop trigger if exists community_members_after_insert on public.community_members;
create trigger community_members_after_insert after insert on public.community_members
  for each row execute function public.on_community_member_insert();

create or replace function public.on_community_member_delete()
returns trigger language plpgsql as $$
begin
  update public.communities set members_count = greatest(members_count - 1, 0) where id = old.community_id;
  return old;
end;
$$;
drop trigger if exists community_members_after_delete on public.community_members;
create trigger community_members_after_delete after delete on public.community_members
  for each row execute function public.on_community_member_delete();

create or replace function public.on_poll_vote_insert()
returns trigger language plpgsql as $$
begin
  update public.poll_options set votes_count = votes_count + 1 where id = new.option_id;
  return new;
end;
$$;
drop trigger if exists poll_votes_after_insert on public.poll_votes;
create trigger poll_votes_after_insert after insert on public.poll_votes
  for each row execute function public.on_poll_vote_insert();

-- notify on new follower
create or replace function public.notify_on_follow()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, actor_id, type)
  values (new.following_id, new.follower_id, 'follow');
  return new;
end;
$$;
drop trigger if exists follows_notify on public.follows;
create trigger follows_notify after insert on public.follows
  for each row execute function public.notify_on_follow();

-- notify on like (skip self-likes)
create or replace function public.notify_on_like()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  post_author uuid;
begin
  select author_id into post_author from public.posts where id = new.post_id;
  if post_author is not null and post_author <> new.user_id then
    insert into public.notifications (user_id, actor_id, type, post_id)
    values (post_author, new.user_id, 'like', new.post_id);
  end if;
  return new;
end;
$$;
drop trigger if exists likes_notify on public.likes;
create trigger likes_notify after insert on public.likes
  for each row execute function public.notify_on_like();

-- notify on comment (skip self-comments)
create or replace function public.notify_on_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  post_author uuid;
begin
  select author_id into post_author from public.posts where id = new.post_id;
  if post_author is not null and post_author <> new.author_id then
    insert into public.notifications (user_id, actor_id, type, post_id)
    values (post_author, new.author_id, 'comment', new.post_id);
  end if;
  return new;
end;
$$;
drop trigger if exists comments_notify on public.comments;
create trigger comments_notify after insert on public.comments
  for each row execute function public.notify_on_comment();

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.notifications enable row level security;

-- COMMUNITIES: public read; only the creator can create/update/delete
drop policy if exists "communities publicly readable" on public.communities;
create policy "communities publicly readable"
  on public.communities for select
  using (status in ('ACTIVE','UNDER_REVIEW'));

drop policy if exists "users create communities" on public.communities;
create policy "users create communities"
  on public.communities for insert
  with check (auth.uid() = creator_id);

drop policy if exists "creator updates community" on public.communities;
create policy "creator updates community"
  on public.communities for update
  using (auth.uid() = creator_id)
  with check (auth.uid() = creator_id);

-- COMMUNITY_MEMBERS: public read; a user can only add/remove themself
drop policy if exists "members publicly readable" on public.community_members;
create policy "members publicly readable"
  on public.community_members for select
  using (true);

drop policy if exists "users join communities" on public.community_members;
create policy "users join communities"
  on public.community_members for insert
  with check (auth.uid() = user_id);

drop policy if exists "users leave communities" on public.community_members;
create policy "users leave communities"
  on public.community_members for delete
  using (auth.uid() = user_id);

-- POLLS: public read; author-only insert
drop policy if exists "polls publicly readable" on public.polls;
create policy "polls publicly readable"
  on public.polls for select
  using (status = 'ACTIVE');

drop policy if exists "users create polls" on public.polls;
create policy "users create polls"
  on public.polls for insert
  with check (auth.uid() = author_id);

-- POLL_OPTIONS: public read; insert only allowed alongside a poll owned by the caller
drop policy if exists "poll options publicly readable" on public.poll_options;
create policy "poll options publicly readable"
  on public.poll_options for select
  using (true);

drop policy if exists "users create own poll options" on public.poll_options;
create policy "users create own poll options"
  on public.poll_options for insert
  with check (exists (select 1 from public.polls where polls.id = poll_id and polls.author_id = auth.uid()));

-- POLL_VOTES: public read (so results are visible); a user can only cast their own vote, once
drop policy if exists "poll votes publicly readable" on public.poll_votes;
create policy "poll votes publicly readable"
  on public.poll_votes for select
  using (true);

drop policy if exists "users cast own vote" on public.poll_votes;
create policy "users cast own vote"
  on public.poll_votes for insert
  with check (auth.uid() = user_id);

-- NOTIFICATIONS: strictly private to the recipient; no direct client
-- inserts (only the security-definer trigger functions write rows);
-- the recipient can update is_read on their own notifications
drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications"
  on public.notifications for select
  using (auth.uid() = user_id);

drop policy if exists "no direct notification inserts" on public.notifications;
create policy "no direct notification inserts"
  on public.notifications for insert
  with check (false);

drop policy if exists "users mark own notifications read" on public.notifications;
create policy "users mark own notifications read"
  on public.notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
