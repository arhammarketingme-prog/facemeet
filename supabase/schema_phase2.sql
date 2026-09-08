-- ============================================================
-- NEXUS — Phase 2 Schema
-- Posts, feed, likes, comments, follow
-- Run AFTER schema.sql (Phase 1) in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- POSTS
-- ------------------------------------------------------------
create table if not exists public.posts (
  id uuid primary key default uuid_generate_v4(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  post_type text not null default 'text' check (post_type in ('text','image','link','poll','question')),
  media_url text,
  link_url text,
  is_demo boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','REPORTED','UNDER_REVIEW','REMOVED')),
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists posts_author_idx on public.posts (author_id);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_status_idx on public.posts (status);

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
  before update on public.posts
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- FOLLOWS
-- ------------------------------------------------------------
create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint no_self_follow check (follower_id <> following_id)
);

create index if not exists follows_following_idx on public.follows (following_id);

-- ------------------------------------------------------------
-- LIKES
-- ------------------------------------------------------------
create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- ------------------------------------------------------------
-- COMMENTS
-- ------------------------------------------------------------
create table if not exists public.comments (
  id uuid primary key default uuid_generate_v4(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1000),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','REPORTED','UNDER_REVIEW','REMOVED')),
  created_at timestamptz not null default now()
);

create index if not exists comments_post_idx on public.comments (post_id);

-- ------------------------------------------------------------
-- COUNTER TRIGGERS
-- keep profiles.channel_posts_count, posts.likes_count,
-- posts.comments_count and profiles.channel_followers_count in sync
-- ------------------------------------------------------------
create or replace function public.on_post_insert()
returns trigger language plpgsql as $$
begin
  update public.profiles set channel_posts_count = channel_posts_count + 1 where id = new.author_id;
  return new;
end;
$$;
drop trigger if exists posts_after_insert on public.posts;
create trigger posts_after_insert after insert on public.posts
  for each row execute function public.on_post_insert();

create or replace function public.on_post_delete()
returns trigger language plpgsql as $$
begin
  update public.profiles set channel_posts_count = greatest(channel_posts_count - 1, 0) where id = old.author_id;
  return old;
end;
$$;
drop trigger if exists posts_after_delete on public.posts;
create trigger posts_after_delete after delete on public.posts
  for each row execute function public.on_post_delete();

create or replace function public.on_like_insert()
returns trigger language plpgsql as $$
begin
  update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  return new;
end;
$$;
drop trigger if exists likes_after_insert on public.likes;
create trigger likes_after_insert after insert on public.likes
  for each row execute function public.on_like_insert();

create or replace function public.on_like_delete()
returns trigger language plpgsql as $$
begin
  update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;
drop trigger if exists likes_after_delete on public.likes;
create trigger likes_after_delete after delete on public.likes
  for each row execute function public.on_like_delete();

create or replace function public.on_comment_insert()
returns trigger language plpgsql as $$
begin
  update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  return new;
end;
$$;
drop trigger if exists comments_after_insert on public.comments;
create trigger comments_after_insert after insert on public.comments
  for each row execute function public.on_comment_insert();

create or replace function public.on_comment_delete()
returns trigger language plpgsql as $$
begin
  update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;
drop trigger if exists comments_after_delete on public.comments;
create trigger comments_after_delete after delete on public.comments
  for each row execute function public.on_comment_delete();

create or replace function public.on_follow_insert()
returns trigger language plpgsql as $$
begin
  update public.profiles set channel_followers_count = channel_followers_count + 1 where id = new.following_id;
  return new;
end;
$$;
drop trigger if exists follows_after_insert on public.follows;
create trigger follows_after_insert after insert on public.follows
  for each row execute function public.on_follow_insert();

create or replace function public.on_follow_delete()
returns trigger language plpgsql as $$
begin
  update public.profiles set channel_followers_count = greatest(channel_followers_count - 1, 0) where id = old.following_id;
  return old;
end;
$$;
drop trigger if exists follows_after_delete on public.follows;
create trigger follows_after_delete after delete on public.follows
  for each row execute function public.on_follow_delete();

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.posts enable row level security;
alter table public.follows enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;

-- POSTS: public read of active posts; owner can insert/update/delete their own
drop policy if exists "posts publicly readable" on public.posts;
create policy "posts publicly readable"
  on public.posts for select
  using (status in ('ACTIVE','REPORTED','UNDER_REVIEW'));

drop policy if exists "users insert own posts" on public.posts;
create policy "users insert own posts"
  on public.posts for insert
  with check (auth.uid() = author_id);

drop policy if exists "users update own posts" on public.posts;
create policy "users update own posts"
  on public.posts for update
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

drop policy if exists "users delete own posts" on public.posts;
create policy "users delete own posts"
  on public.posts for delete
  using (auth.uid() = author_id);

-- FOLLOWS: readable by anyone (social graph is public), only the
-- follower can create/remove their own follow relationship
drop policy if exists "follows publicly readable" on public.follows;
create policy "follows publicly readable"
  on public.follows for select
  using (true);

drop policy if exists "users create own follows" on public.follows;
create policy "users create own follows"
  on public.follows for insert
  with check (auth.uid() = follower_id);

drop policy if exists "users delete own follows" on public.follows;
create policy "users delete own follows"
  on public.follows for delete
  using (auth.uid() = follower_id);

-- LIKES: readable by anyone, only the liker can create/remove their own like
drop policy if exists "likes publicly readable" on public.likes;
create policy "likes publicly readable"
  on public.likes for select
  using (true);

drop policy if exists "users create own likes" on public.likes;
create policy "users create own likes"
  on public.likes for insert
  with check (auth.uid() = user_id);

drop policy if exists "users delete own likes" on public.likes;
create policy "users delete own likes"
  on public.likes for delete
  using (auth.uid() = user_id);

-- COMMENTS: public read of active comments; owner can insert/delete their own
drop policy if exists "comments publicly readable" on public.comments;
create policy "comments publicly readable"
  on public.comments for select
  using (status in ('ACTIVE','REPORTED','UNDER_REVIEW'));

drop policy if exists "users insert own comments" on public.comments;
create policy "users insert own comments"
  on public.comments for insert
  with check (auth.uid() = author_id);

drop policy if exists "users delete own comments" on public.comments;
create policy "users delete own comments"
  on public.comments for delete
  using (auth.uid() = author_id);
