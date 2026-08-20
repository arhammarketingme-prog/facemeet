-- ============================================================
-- NEXUS — Phase 7 Schema
-- E2E messaging metadata, moderation (block/report)
-- Run AFTER phases 1–4 and 6.
-- ============================================================

-- ------------------------------------------------------------
-- E2E MESSAGING
-- The server stores only ciphertext + a per-recipient wrapped
-- key. It never receives plaintext (spec §5) — encryption and
-- decryption happen entirely in the browser via Web Crypto API.
-- profiles.public_key holds each user's RSA-OAEP public key
-- (JWK, as text) so others can encrypt to them.
-- ------------------------------------------------------------
alter table public.profiles add column if not exists public_key text;

create table if not exists public.messages_metadata (
  id uuid primary key default uuid_generate_v4(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  ciphertext text not null,       -- AES-GCM encrypted message body, base64
  iv text not null,               -- AES-GCM IV, base64
  key_for_recipient text not null, -- AES key wrapped with recipient's RSA public key, base64
  key_for_sender text not null,    -- same AES key wrapped with sender's own public key, so senders can re-read their own sent messages
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint no_self_message check (sender_id <> recipient_id)
);
create index if not exists messages_conversation_idx on public.messages_metadata (sender_id, recipient_id, created_at desc);
create index if not exists messages_recipient_idx on public.messages_metadata (recipient_id, created_at desc);

alter table public.messages_metadata enable row level security;

drop policy if exists "users read own messages" on public.messages_metadata;
create policy "users read own messages"
  on public.messages_metadata for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "users send own messages" on public.messages_metadata;
create policy "users send own messages"
  on public.messages_metadata for insert
  with check (auth.uid() = sender_id);

drop policy if exists "recipient marks read" on public.messages_metadata;
create policy "recipient marks read"
  on public.messages_metadata for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

-- ------------------------------------------------------------
-- BLOCKS
-- ------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

alter table public.blocks enable row level security;
drop policy if exists "users read own blocks" on public.blocks;
create policy "users read own blocks" on public.blocks for select using (auth.uid() = blocker_id);
drop policy if exists "users create own blocks" on public.blocks;
create policy "users create own blocks" on public.blocks for insert with check (auth.uid() = blocker_id);
drop policy if exists "users remove own blocks" on public.blocks;
create policy "users remove own blocks" on public.blocks for delete using (auth.uid() = blocker_id);

-- ------------------------------------------------------------
-- REPORTS
-- ------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default uuid_generate_v4(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post','comment','user','community')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 1 and 300),
  status text not null default 'REPORTED' check (status in ('REPORTED','UNDER_REVIEW','REMOVED','DISMISSED')),
  created_at timestamptz not null default now()
);
create index if not exists reports_target_idx on public.reports (target_type, target_id);

alter table public.reports enable row level security;
drop policy if exists "users read own reports" on public.reports;
create policy "users read own reports" on public.reports for select using (auth.uid() = reporter_id);
drop policy if exists "users file reports" on public.reports;
create policy "users file reports" on public.reports for insert with check (auth.uid() = reporter_id);
-- no update/delete policy — only reviewable via the Supabase dashboard/SQL editor for now;
-- a full admin review queue is a future phase.
