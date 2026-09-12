-- ============================================================
-- VARTEX — Phase 20 Schema
-- Verified badges, profile-view log, community moderator role
-- management. Run AFTER phase 19.
-- ============================================================

-- ------------------------------------------------------------
-- EMAIL NOTIFICATION PREFERENCE
-- Plain user preference, not privileged — no guard needed.
-- ------------------------------------------------------------
alter table public.profiles add column if not exists email_notifications boolean not null default true;

-- ------------------------------------------------------------
-- VERIFIED BADGE (admin-only)
-- ------------------------------------------------------------
alter table public.profiles add column if not exists is_verified boolean not null default false;

-- extend the Phase 16 guard so is_verified can only ever be set
-- by an admin or a legitimate system write — same protection as
-- is_admin/status/the counters
create or replace function public.guard_profile_columns()
returns trigger language plpgsql as $$
begin
  if not public.is_admin(auth.uid()) and not public.is_system_write() then
    new.is_admin := old.is_admin;
    new.status := old.status;
    new.is_verified := old.is_verified;
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
-- (trigger already exists from Phase 16, no need to recreate it —
-- create or replace on the function is enough)

-- ------------------------------------------------------------
-- PROFILE VIEW LOG (who viewed your profile)
-- Only the profile owner can ever read this. A view from a
-- signed-out visitor is logged with viewer_id = null and shows
-- as "Someone" rather than exposing nothing at all.
-- ------------------------------------------------------------
create table if not exists public.profile_views (
  id uuid primary key default uuid_generate_v4(),
  viewer_id uuid references public.profiles(id) on delete set null,
  viewed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists profile_views_viewed_idx on public.profile_views (viewed_id, created_at desc);

alter table public.profile_views enable row level security;
drop policy if exists "owner reads own profile views" on public.profile_views;
create policy "owner reads own profile views"
  on public.profile_views for select
  using (auth.uid() = viewed_id);
-- no insert policy for any client role — only increment_profile_view (security definer) writes here

create or replace function public.increment_profile_view(target_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.profiles set channel_views_count = channel_views_count + 1 where id = target_id;
  if auth.uid() is null or auth.uid() <> target_id then
    insert into public.profile_views (viewer_id, viewed_id) values (auth.uid(), target_id);
  end if;
end;
$$;
grant execute on function public.increment_profile_view(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- COMMUNITY MODERATOR ROLE MANAGEMENT
-- community_members never had an UPDATE policy at all, so a
-- community's admin/creator had no way to actually promote
-- someone to moderator. Add one, scoped to admins of that
-- specific community only, and only able to touch the `role`
-- column (not silently reassign someone else's membership row
-- to a different community, etc.).
-- ------------------------------------------------------------
create or replace function public.guard_community_member_columns()
returns trigger language plpgsql as $$
begin
  new.community_id := old.community_id;
  new.user_id := old.user_id;
  new.joined_at := old.joined_at;
  return new;
end;
$$;
drop trigger if exists community_members_guard_columns on public.community_members;
create trigger community_members_guard_columns before update on public.community_members
  for each row execute function public.guard_community_member_columns();

drop policy if exists "community admins manage member roles" on public.community_members;
create policy "community admins manage member roles"
  on public.community_members for update
  using (exists (
    select 1 from public.community_members cm
    where cm.community_id = community_members.community_id
      and cm.user_id = auth.uid()
      and cm.role = 'admin'
  ));
