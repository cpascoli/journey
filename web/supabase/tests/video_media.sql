-- Video media: commit_media_upload_v2's kind/duration handling, the
-- cleanup-race guard it inherits, and that an invite's all-tags rule governs
-- a video exactly as it governs a photo.
-- Run only against the local stack with all migrations applied.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family'),
  ('00000000-0000-0000-0000-00000000f002', 'Sport');

insert into public.entries (id, occurred_at, day, visibility) values
  ('00000000-0000-0000-0000-00000000e001', now(), current_date, 'shared');

insert into public.entry_tags (entry_id, tag_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000f001');

insert into public.invites (id, name, token_hash) values
  ('00000000-0000-0000-0000-00000000a001', 'Family', 'family-hash'),
  ('00000000-0000-0000-0000-00000000a002', 'Sport', 'sport-hash');

insert into public.invite_tags (invite_id, tag_id) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000f002');

do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  video_path constant text := 'r2:entries/e001/vid/v1.mp4';
  replacement_path constant text := 'r2:entries/e001/vid/v2.mp4';
  photo_path constant text := 'entries/e001/pic/p1.jpg';
  row_found record;
  replaced text;
begin
  -- A video records its kind, duration and content type.
  perform public.prepare_media_upload(v_entry, video_path);
  perform public.commit_media_upload_v2(
    v_entry, 'vid', video_path, 'video', 'video/mp4', 720, 1280, 12.5, now(), 1);

  select em.kind, em.storage_path, em.width, em.height, em.duration_seconds, em.content_type
    into row_found
  from public.entry_media em where em.entry_id = v_entry and em.asset_key = 'vid';
  if row_found.kind <> 'video' then
    raise exception 'video must be stored as kind video, got %', row_found.kind;
  end if;
  if row_found.duration_seconds <> 12.5 then
    raise exception 'video duration must be recorded, got %', row_found.duration_seconds;
  end if;
  if row_found.width <> 720 or row_found.height <> 1280 then
    raise exception 'portrait dimensions must survive as given';
  end if;

  -- The same function still writes photos, which have no duration.
  perform public.prepare_media_upload(v_entry, photo_path);
  perform public.commit_media_upload_v2(
    v_entry, 'pic', photo_path, 'photo', 'image/jpeg', 2048, 1536, null, now(), 0);
  if (select em.kind from public.entry_media em where em.asset_key = 'pic') <> 'photo' then
    raise exception 'photos must still commit as photos';
  end if;
  if (select em.duration_seconds from public.entry_media em where em.asset_key = 'pic') is not null then
    raise exception 'a photo must have no duration';
  end if;

  -- Replacing a video hands back the old object for cleanup.
  perform public.prepare_media_upload(v_entry, replacement_path);
  select replaced_storage_path into replaced from public.commit_media_upload_v2(
    v_entry, 'vid', replacement_path, 'video', 'video/mp4', 720, 1280, 9, now(), 1);
  if replaced is distinct from video_path then
    raise exception 'replacing a video must return the previous path, got %', replaced;
  end if;
  if not exists (
    select 1 from public.storage_cleanup_queue q where q.storage_path = video_path
  ) then
    raise exception 'the replaced video must be queued for removal';
  end if;
end $$;

-- A path a cleanup worker has claimed can no longer be committed: otherwise a
-- media row could end up pointing at an object being deleted.
do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  claimed constant text := 'r2:entries/e001/vid/v3.mp4';
begin
  perform public.prepare_media_upload(v_entry, claimed);
  update public.storage_cleanup_queue q set claimed_at = now() where q.storage_path = claimed;
  begin
    perform public.commit_media_upload_v2(
      v_entry, 'raced', claimed, 'video', 'video/mp4', 720, 1280, 3, now(), 2);
    raise exception 'committing a claimed path must fail';
  exception when sqlstate '55000' then
    null; -- expected
  end;
  if exists (select 1 from public.entry_media em where em.asset_key = 'raced') then
    raise exception 'a refused commit must leave no media row';
  end if;
end $$;

-- Videos obey the same all-tags rule as photos.
do $$
begin
  if (select count(*) from public.media_visible_to_invite(
    'family-hash', '00000000-0000-0000-0000-00000000e001', 'vid'
  )) <> 1 then
    raise exception 'a fully tagged invite should see the video';
  end if;
  if (select count(*) from public.media_visible_to_invite(
    'sport-hash', '00000000-0000-0000-0000-00000000e001', 'vid'
  )) <> 0 then
    raise exception 'an under-tagged invite must not see the video';
  end if;
end $$;

-- The new write function is service-role only, like every other one.
do $$
declare
  signature constant text :=
    'public.commit_media_upload_v2(uuid,text,text,public.media_kind,text,integer,integer,numeric,timestamptz,integer)';
begin
  if has_function_privilege('anon', signature, 'execute')
    or has_function_privilege('authenticated', signature, 'execute') then
    raise exception 'public roles must not execute media writes';
  end if;
  if not has_function_privilege('service_role', signature, 'execute') then
    raise exception 'service_role must execute media writes';
  end if;
end $$;

select 'video_media.sql: all checks passed' as result;

rollback;
