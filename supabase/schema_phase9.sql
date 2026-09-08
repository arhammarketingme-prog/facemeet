-- ============================================================
-- NEXUS — Phase 9 Schema
-- Message notifications, saved posts (bookmarking), demo polls.
-- Run AFTER phases 1–4, 6, 7.
-- ============================================================

-- ------------------------------------------------------------
-- MESSAGE NOTIFICATIONS
-- Extend the notifications type list, then notify the recipient
-- whenever a new encrypted message arrives. The notification
-- itself never contains message content — just "you got a
-- message from X" — since Nexus can't read the ciphertext either.
-- ------------------------------------------------------------
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('follow','like','comment','community_join','poll_vote','message'));

create or replace function public.notify_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, actor_id, type)
  values (new.recipient_id, new.sender_id, 'message');
  return new;
end;
$$;
drop trigger if exists messages_notify on public.messages_metadata;
create trigger messages_notify after insert on public.messages_metadata
  for each row execute function public.notify_on_message();

-- ------------------------------------------------------------
-- SAVED POSTS (bookmarking)
-- ------------------------------------------------------------
create table if not exists public.saved_posts (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

alter table public.saved_posts enable row level security;
drop policy if exists "users read own saved posts" on public.saved_posts;
create policy "users read own saved posts" on public.saved_posts for select using (auth.uid() = user_id);
drop policy if exists "users save posts" on public.saved_posts;
create policy "users save posts" on public.saved_posts for insert with check (auth.uid() = user_id);
drop policy if exists "users unsave posts" on public.saved_posts;
create policy "users unsave posts" on public.saved_posts for delete using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- DEMO POLLS (landing-page preview only — separate from the
-- real polls table, same reasoning as demo_accounts/demo_posts:
-- never mixed with real user data, public read-only)
-- ------------------------------------------------------------
create table if not exists public.demo_polls (
  id uuid primary key default uuid_generate_v4(),
  demo_account_id uuid references public.demo_accounts(id) on delete cascade,
  question text not null,
  category text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.demo_poll_options (
  id uuid primary key default uuid_generate_v4(),
  demo_poll_id uuid not null references public.demo_polls(id) on delete cascade,
  option_text text not null,
  votes_count integer not null default 0,
  position integer not null default 0
);

alter table public.demo_polls enable row level security;
alter table public.demo_poll_options enable row level security;
drop policy if exists "demo polls publicly readable" on public.demo_polls;
create policy "demo polls publicly readable" on public.demo_polls for select using (true);
drop policy if exists "demo poll options publicly readable" on public.demo_poll_options;
create policy "demo poll options publicly readable" on public.demo_poll_options for select using (true);

-- seed ~20 sample demo polls with 2–4 options each, picking random
-- existing demo accounts as the "author" for texture
do $$
declare
  v_poll_id uuid;
  v_account_id uuid;
  questions text[] := array[
    'Which topic would you like to see more of?|Technology|Business|Lifestyle|Sports',
    'Best time to post for engagement?|Morning|Afternoon|Evening|Late night',
    'What matters most in a creator platform?|Privacy|Reach|Monetization|Community',
    'Favorite way to discover new creators?|Search|Explore page|Communities|Recommendations',
    'How often do you check your feed?|Multiple times a day|Once a day|Few times a week|Rarely',
    'What content format do you enjoy most?|Text posts|Polls|Short videos|Articles',
    'Which Maharashtra city has the best startup scene?|Pune|Mumbai|Nashik|Nagpur',
    'Preferred way to earn as a creator?|Ad revenue|Referrals|Brand deals|Community support',
    'What would improve your experience most?|Faster feed|Better search|More communities|Dark mode',
    'Which skill are you most interested in learning?|AI/ML|Design|Marketing|Coding'
  ];
  parts text[];
  i int;
  j int;
begin
  truncate table public.demo_poll_options, public.demo_polls;

  for i in 1..array_length(questions,1) loop
    parts := string_to_array(questions[i], '|');
    select id into v_account_id from public.demo_accounts order by random() limit 1;

    insert into public.demo_polls (demo_account_id, question, category)
    values (v_account_id, parts[1], 'General')
    returning id into v_poll_id;

    for j in 2..array_length(parts,1) loop
      insert into public.demo_poll_options (demo_poll_id, option_text, votes_count, position)
      values (v_poll_id, parts[j], floor(random() * 3000)::int, j - 2);
    end loop;
  end loop;
end $$;
