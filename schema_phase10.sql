-- ============================================================
-- NEXUS — Phase 10 Schema
-- Admin role + moderation powers, real ad-campaign payments
-- (Razorpay). Run AFTER phases 1–4, 6, 7, 9.
-- ============================================================

-- ------------------------------------------------------------
-- ADMIN ROLE
-- No signup flow grants this — bootstrap your first admin by
-- running, once, in the SQL editor:
--   update public.profiles set is_admin = true where username = 'yourusername';
-- ------------------------------------------------------------
alter table public.profiles add column if not exists is_admin boolean not null default false;

create or replace function public.is_admin(uid uuid)
returns boolean language sql stable as $$
  select coalesce((select is_admin from public.profiles where id = uid), false);
$$;

-- admins can update ANY profile (to suspend a user), in addition
-- to the existing "users update own profile" policy
drop policy if exists "admins update any profile" on public.profiles;
create policy "admins update any profile"
  on public.profiles for update
  using (public.is_admin(auth.uid()))
  with check (true);

-- admins can moderate (remove) any post
drop policy if exists "admins moderate posts" on public.posts;
create policy "admins moderate posts"
  on public.posts for update
  using (public.is_admin(auth.uid()));

drop policy if exists "admins moderate comments" on public.comments;
create policy "admins moderate comments"
  on public.comments for update
  using (public.is_admin(auth.uid()));

drop policy if exists "admins moderate communities" on public.communities;
create policy "admins moderate communities"
  on public.communities for update
  using (public.is_admin(auth.uid()));

-- admins can see and act on ALL reports, not just their own
drop policy if exists "admins read all reports" on public.reports;
create policy "admins read all reports"
  on public.reports for select
  using (auth.uid() = reporter_id or public.is_admin(auth.uid()));

drop policy if exists "admins update reports" on public.reports;
create policy "admins update reports"
  on public.reports for update
  using (public.is_admin(auth.uid()));

-- ------------------------------------------------------------
-- AD CAMPAIGN PAYMENTS (Razorpay)
-- Written only by the verify-razorpay-payment Edge Function,
-- which runs with the service-role key server-side — never by
-- the client directly, so a payment record can't be forged by
-- calling the table straight from the browser.
-- ------------------------------------------------------------
create table if not exists public.ad_payments (
  id uuid primary key default uuid_generate_v4(),
  campaign_id uuid not null references public.ad_campaigns(id) on delete cascade,
  amount_inr integer not null,
  razorpay_order_id text not null,
  razorpay_payment_id text,
  status text not null default 'created' check (status in ('created','paid','failed')),
  created_at timestamptz not null default now()
);
create index if not exists ad_payments_campaign_idx on public.ad_payments (campaign_id);

alter table public.ad_payments enable row level security;
drop policy if exists "advertiser reads own payments" on public.ad_payments;
create policy "advertiser reads own payments"
  on public.ad_payments for select
  using (exists (
    select 1 from public.ad_campaigns c
    join public.advertisers a on a.id = c.advertiser_id
    where c.id = campaign_id and a.user_id = auth.uid()
  ));
-- no insert/update policy for any client role — Edge Function only (service role bypasses RLS)
