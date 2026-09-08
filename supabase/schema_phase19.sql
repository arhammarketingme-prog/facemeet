-- ============================================================
-- NEXUS — Phase 19 Schema — same column-guard pattern, notifications
--
-- "users mark own notifications read" (Phase 3) checks whose
-- notification row is being updated, not which column. A user
-- could rewrite their own notification's actor_id/type/post_id to
-- say anything — low real-world impact since it's only ever shown
-- to themselves, but it's the same unguarded pattern as the
-- Phase 16/17 fixes, so closing it for consistency. The only
-- column a recipient should ever change is is_read.
--
-- Run AFTER phase 18.
-- ============================================================

create or replace function public.guard_notification_integrity()
returns trigger language plpgsql as $$
begin
  new.user_id := old.user_id;
  new.actor_id := old.actor_id;
  new.type := old.type;
  new.post_id := old.post_id;
  new.community_id := old.community_id;
  new.created_at := old.created_at;
  return new;
end;
$$;
drop trigger if exists notifications_guard_integrity on public.notifications;
create trigger notifications_guard_integrity before update on public.notifications
  for each row execute function public.guard_notification_integrity();
