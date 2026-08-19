-- ============================================================
-- NEXUS — Phase 4 Schema + Seed
-- Demo/AI seed ecosystem — kept in its OWN tables, never mixed
-- with real user data (spec §38–41: demo rows must never share
-- a table with real accounts/posts/earnings).
-- Run AFTER schema.sql, schema_phase2.sql, schema_phase3.sql.
-- ============================================================

-- ------------------------------------------------------------
-- DEMO ACCOUNTS
-- Never linked to auth.users — these are not real, loginable
-- accounts. Every row is unambiguously a demo persona.
-- ------------------------------------------------------------
create table if not exists public.demo_accounts (
  id uuid primary key default uuid_generate_v4(),
  username text unique not null,
  display_name text not null,
  bio text not null default '',
  category text not null,
  avatar_hue integer not null default 30,
  channel_name text not null default '',
  followers_count integer not null default 0,
  following_count integer not null default 0,
  posts_count integer not null default 0,
  views_count integer not null default 0,
  engagement_pct numeric(4,1) not null default 0,
  demo_ad_revenue_inr integer not null default 0,
  demo_referral_inr integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists demo_accounts_category_idx on public.demo_accounts (category);

-- ------------------------------------------------------------
-- DEMO POSTS
-- ------------------------------------------------------------
create table if not exists public.demo_posts (
  id uuid primary key default uuid_generate_v4(),
  demo_account_id uuid not null references public.demo_accounts(id) on delete cascade,
  category text not null,
  content text not null,
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists demo_posts_account_idx on public.demo_posts (demo_account_id);
create index if not exists demo_posts_created_idx on public.demo_posts (created_at desc);

-- ------------------------------------------------------------
-- DEMO COMMENTS (a couple of canned replies per post, for texture)
-- ------------------------------------------------------------
create table if not exists public.demo_comments (
  id uuid primary key default uuid_generate_v4(),
  demo_post_id uuid not null references public.demo_posts(id) on delete cascade,
  demo_account_id uuid not null references public.demo_accounts(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);
create index if not exists demo_comments_post_idx on public.demo_comments (demo_post_id);

-- ------------------------------------------------------------
-- DEMO COMMUNITIES
-- ------------------------------------------------------------
create table if not exists public.demo_communities (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  description text not null default '',
  category text not null,
  members_count integer not null default 0,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY — all demo tables are public read-only.
-- No insert/update/delete policies are created for any role,
-- which means the client can never write to them; only this
-- seed script (running as the table owner) can.
-- ------------------------------------------------------------
alter table public.demo_accounts enable row level security;
alter table public.demo_posts enable row level security;
alter table public.demo_comments enable row level security;
alter table public.demo_communities enable row level security;

drop policy if exists "demo accounts publicly readable" on public.demo_accounts;
create policy "demo accounts publicly readable" on public.demo_accounts for select using (true);

drop policy if exists "demo posts publicly readable" on public.demo_posts;
create policy "demo posts publicly readable" on public.demo_posts for select using (true);

drop policy if exists "demo comments publicly readable" on public.demo_comments;
create policy "demo comments publicly readable" on public.demo_comments for select using (true);

drop policy if exists "demo communities publicly readable" on public.demo_communities;
create policy "demo communities publicly readable" on public.demo_communities for select using (true);

-- ============================================================
-- SEED GENERATOR
-- Generates ~1,000 demo personas, ~2,500 demo posts, a couple
-- of canned comments per post, and ~24 demo communities.
-- Names are generic first+last name combinations (not real
-- people), bios/posts are template-based "sample analysis"
-- style content per spec §12 — never framed as real news or
-- attributed to a real person.
-- Safe to re-run: it clears prior demo rows first.
-- ============================================================
truncate table public.demo_comments, public.demo_posts, public.demo_communities, public.demo_accounts;

do $$
declare
  first_names text[] := array['Aarav','Vivaan','Aditya','Sai','Reyansh','Ishaan','Arjun','Rohan','Kunal','Nikhil',
    'Ananya','Diya','Sneha','Priya','Isha','Riya','Meera','Kavya','Anjali','Pooja',
    'Om','Yash','Aryan','Karan','Rahul','Siddharth','Varun','Tejas','Abhinav','Sameer',
    'Neha','Shreya','Pallavi','Swati','Radhika','Nisha','Komal','Vaishnavi','Sanika','Gauri'];
  last_names text[] := array['Patil','Deshmukh','Kulkarni','Joshi','Shah','Gaikwad','Jadhav','More','Pawar','Chavan',
    'Kale','Bhosale','Shinde','Sharma','Verma','Gupta','Kumar','Iyer','Nair','Reddy'];
  categories text[] := array['Technology','AI','Business','Finance','Education','Jobs','Sports','Gaming',
    'Entertainment','Maharashtra','India','World','Travel','Food','Lifestyle',
    'Entrepreneurship','Agriculture','Science','Creator Economy','News'];
  cities text[] := array['Satara','Pune','Kolhapur','Nashik','Nagpur','Aurangabad','Solapur','Sangli','Mumbai','Thane'];
  bio_templates text[] := array[
    'Sharing sample %s insights and demo analysis for the community. AI DEMO persona.',
    'Demo creator exploring %s topics — sample content for illustration only.',
    'AI-generated %s explainer account. Not a real person — sample profile.',
    'Illustrative %s channel used to preview the Nexus feed. DEMO account.'];
  post_templates text[] := array[
    'DEMO ANALYSIS: here''s a sample breakdown of a recent %s trend and what it could mean for everyday readers.',
    'SAMPLE POST — a quick illustrative take on what''s moving in %s this week.',
    'AI DEMO: three things worth watching in %s right now, explained simply.',
    'Demo content: a short sample thread on %s for newcomers to the topic.',
    'ILLUSTRATIVE POST — what a %s update might look like on a real creator channel.'];
  comment_templates text[] := array['Interesting, thanks for the sample breakdown!','Demo comment — good illustrative point.','Nice, this is a helpful sample explainer.'];

  community_names text[] := array['Maharashtra Entrepreneurs','AI India','Gaming Hub','Students India','Farmers Community',
    'Tech Explorers','Finance Circle','Creator Collective','Sports Fans Maharashtra','Food Lovers India',
    'Travel Diaries','Startup Founders','Science Curious','Education Network','Local Jobs Board',
    'Marathi Creators','Cricket Talk','Bollywood Buzz','Agri Innovators','World News Watch',
    'Lifestyle & Wellness','Coding Community','Small Business Owners','News Explained'];

  v_category text;
  v_username text;
  v_display_name text;
  v_account_id uuid;
  v_post_id uuid;
  v_post_count int;
  i int;
  j int;
begin
  for i in 1..1000 loop
    v_category := categories[1 + floor(random() * array_length(categories,1))::int];
    v_display_name := first_names[1 + floor(random() * array_length(first_names,1))::int] || ' ' ||
                       last_names[1 + floor(random() * array_length(last_names,1))::int];
    v_username := lower(regexp_replace(v_display_name, '\s+', '', 'g')) || i::text;

    insert into public.demo_accounts (
      username, display_name, bio, category, avatar_hue, channel_name,
      followers_count, following_count, posts_count, views_count, engagement_pct,
      demo_ad_revenue_inr, demo_referral_inr
    ) values (
      v_username, v_display_name,
      format(bio_templates[1 + floor(random() * array_length(bio_templates,1))::int], v_category),
      v_category,
      floor(random() * 360)::int,
      v_display_name || ' — ' || v_category,
      floor(random() * 50000)::int,
      floor(random() * 500)::int,
      0, -- filled in as posts are generated below
      floor(random() * 200000)::int,
      round((random() * 12)::numeric, 1),
      floor(random() * 3000)::int,
      floor(random() * 800)::int
    ) returning id into v_account_id;

    v_post_count := 1 + floor(random() * 3)::int; -- 1–3 posts per account
    for j in 1..v_post_count loop
      insert into public.demo_posts (demo_account_id, category, content, likes_count, comments_count, created_at)
      values (
        v_account_id,
        v_category,
        format(post_templates[1 + floor(random() * array_length(post_templates,1))::int], v_category),
        floor(random() * 4000)::int,
        floor(random() * 120)::int,
        now() - (random() * interval '30 days')
      ) returning id into v_post_id;

      -- a couple of canned demo comments for texture, ~40% of posts
      if random() < 0.4 then
        insert into public.demo_comments (demo_post_id, demo_account_id, content)
        values (v_post_id, v_account_id, comment_templates[1 + floor(random() * array_length(comment_templates,1))::int]);
      end if;
    end loop;

    update public.demo_accounts set posts_count = v_post_count where id = v_account_id;
  end loop;

  for i in 1..array_length(community_names,1) loop
    insert into public.demo_communities (name, description, category, members_count)
    values (
      community_names[i],
      'DEMO community preview — illustrative member count and activity.',
      categories[1 + floor(random() * array_length(categories,1))::int],
      50 + floor(random() * 5000)::int
    );
  end loop;
end $$;
