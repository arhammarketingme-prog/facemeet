-- ============================================================
-- NEXUS — Phase 17 Schema — finishing the Phase 16 follow-up
--
-- Same class of bug as Phase 16, lower stakes: "users update own
-- posts" (Phase 2) lets a post's author directly set likes_count
-- or comments_count via a raw API call — e.g.
--   supabase.from('posts').update({ likes_count: 99999 }).eq('id', myPostId)
-- Impact is cosmetic/trending-manipulation, not money or access
-- control, which is why this was correctly left for a follow-up
-- rather than bundled into the urgent Phase 16 fix. Closing it
-- now for completeness.
--
-- Run AFTER phase 16 (needs is_system_write() from that file).
-- ============================================================

create or replace function public.guard_post_counters()
returns trigger language plpgsql as $$
begin
  if not public.is_admin(auth.uid()) and not public.is_system_write() then
    new.likes_count := old.likes_count;
    new.comments_count := old.comments_count;
    new.status := old.status; -- a user can't un-remove their own moderated/auto-flagged post
  end if;
  return new;
end;
$$;
drop trigger if exists posts_guard_counters on public.posts;
create trigger posts_guard_counters before update on public.posts
  for each row execute function public.guard_post_counters();

-- mark the legitimate system paths (like/unlike, comment/delete-comment)
create or replace function public.on_like_insert()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  return new;
end;
$$;

create or replace function public.on_like_delete()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;

create or replace function public.on_comment_insert()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  return new;
end;
$$;

create or replace function public.on_comment_delete()
returns trigger language plpgsql as $$
begin
  perform set_config('nexus.system_write', 'true', true);
  update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
  return old;
end;
$$;

-- ------------------------------------------------------------
-- MESSAGES_METADATA INTEGRITY
-- "recipient marks read" (Phase 7) checks WHO can update a
-- message row but not WHICH columns — a recipient could rewrite
-- ciphertext/iv/the wrapped keys on a message already sent to
-- them (they hold the AES key, so they CAN produce a validly-
-- decryptable replacement), effectively forging what a sender
-- appears to have said, after the fact. The only column a
-- recipient should ever be able to touch is read_at.
-- ------------------------------------------------------------
create or replace function public.guard_message_integrity()
returns trigger language plpgsql as $$
begin
  new.sender_id := old.sender_id;
  new.recipient_id := old.recipient_id;
  new.ciphertext := old.ciphertext;
  new.iv := old.iv;
  new.key_for_recipient := old.key_for_recipient;
  new.key_for_sender := old.key_for_sender;
  new.created_at := old.created_at;
  return new;
end;
$$;
drop trigger if exists messages_guard_integrity on public.messages_metadata;
create trigger messages_guard_integrity before update on public.messages_metadata
  for each row execute function public.guard_message_integrity();
