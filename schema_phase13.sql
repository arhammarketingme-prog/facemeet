-- ============================================================
-- NEXUS — Phase 13 Schema
-- Social Passport: external platform links on a profile.
-- Run AFTER phases 1–4, 6, 7, 10, 11, 12.
-- ============================================================

alter table public.profiles add column if not exists social_links jsonb not null default '{}'::jsonb;
-- shape: {"youtube": "https://...", "instagram": "https://...", "x": "https://...", "other": "https://..."}
-- These are plain user-entered links, not OAuth-verified connections —
-- shown on the profile as "Connected elsewhere", not as authenticated
-- account links. Real OAuth linking (verified badges per platform) is
-- a separate, much larger integration per platform and is not done here.
