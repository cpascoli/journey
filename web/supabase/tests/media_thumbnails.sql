-- Thumbnails: recording one, replacing it, and making sure the small copy is
-- disposed of with its media row rather than leaking into storage.
-- Run only against the local stack with all migrations applied.

begin;

insert into public.entries (id, occurred_at, day, visibility) values
  ('00000000-0000-0000-0000-00000000e001', now(), current_date, 'shared');

do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  thumb constant text := 'entries/e001/k1/v1-thumb.jpg';
  replacement constant text := 'entries/e001/k1/v2-thumb.jpg';
  result record;
begin
  perform public.prepare_media_upload(v_entry, 'entries/e001/k1/v1.jpg');
  perform public.commit_media_upload_v2(
    v_entry, 'k1', 'entries/e001/k1/v1.jpg', 'photo', 'image/jpeg', 8, 6, null, now(), 0);

  -- A thumbnail is recorded against media that already exists.
  perform public.prepare_media_upload(v_entry, thumb);
  select * into result from public.commit_media_thumbnail(v_entry, 'k1', thumb);
  if not result.committed then
    raise exception 'committing a thumbnail for existing media should succeed';
  end if;
  if (select em.thumb_path from public.entry_media em where em.asset_key = 'k1') <> thumb then
    raise exception 'the thumbnail path should be stored';
  end if;

  -- Replacing it queues the old object rather than orphaning it.
  perform public.prepare_media_upload(v_entry, replacement);
  perform public.commit_media_thumbnail(v_entry, 'k1', replacement);
  if not exists (
    select 1 from public.storage_cleanup_queue q where q.storage_path = thumb
  ) then
    raise exception 'a replaced thumbnail must be queued for removal';
  end if;

  -- Media with no row cannot gain a thumbnail.
  perform public.prepare_media_upload(v_entry, 'entries/e001/nope-thumb.jpg');
  select * into result
  from public.commit_media_thumbnail(v_entry, 'missing-key', 'entries/e001/nope-thumb.jpg');
  if result.committed then
    raise exception 'a thumbnail for unknown media must not report success';
  end if;
end $$;

-- A claimed path cannot be committed, exactly as for the full image.
do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  claimed constant text := 'entries/e001/k1/v3-thumb.jpg';
begin
  perform public.prepare_media_upload(v_entry, claimed);
  update public.storage_cleanup_queue q set claimed_at = now() where q.storage_path = claimed;
  begin
    perform public.commit_media_thumbnail(v_entry, 'k1', claimed);
    raise exception 'committing a claimed path must fail';
  exception when sqlstate '55000' then
    null; -- expected
  end;
end $$;

-- Deleting the media disposes of its thumbnail too.
do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  current_thumb text;
begin
  select em.thumb_path into current_thumb from public.entry_media em where em.asset_key = 'k1';
  perform public.delete_entry_media(v_entry, 'k1');
  if not exists (
    select 1 from public.storage_cleanup_queue q where q.storage_path = current_thumb
  ) then
    raise exception 'deleting media must queue its thumbnail for removal';
  end if;
end $$;

-- Unpublishing an entry takes its thumbnails with it.
do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  thumb constant text := 'entries/e001/k2/v1-thumb.jpg';
begin
  perform public.prepare_media_upload(v_entry, 'entries/e001/k2/v1.jpg');
  perform public.commit_media_upload_v2(
    v_entry, 'k2', 'entries/e001/k2/v1.jpg', 'photo', 'image/jpeg', 8, 6, null, now(), 0);
  perform public.prepare_media_upload(v_entry, thumb);
  perform public.commit_media_thumbnail(v_entry, 'k2', thumb);

  perform public.delete_entry_with_media(v_entry);
  if not exists (
    select 1 from public.storage_cleanup_queue q where q.storage_path = thumb
  ) then
    raise exception 'unpublishing must queue thumbnails for removal';
  end if;
end $$;

-- Authorization still governs the small copy, and now returns it.
do $$
begin
  insert into public.entries (id, occurred_at, day, visibility)
  values ('00000000-0000-0000-0000-00000000e002', now(), current_date, 'shared');
  insert into public.entry_media (entry_id, asset_key, kind, storage_path, thumb_path)
  values ('00000000-0000-0000-0000-00000000e002', 'k1', 'photo',
          'entries/e002/k1.jpg', 'entries/e002/k1-thumb.jpg');
  insert into public.invites (id, name, token_hash)
  values ('00000000-0000-0000-0000-00000000a001', 'Reader', 'reader-hash');

  if (select m.thumb_path from public.media_visible_to_invite(
        'reader-hash', '00000000-0000-0000-0000-00000000e002', 'k1') m)
     <> 'entries/e002/k1-thumb.jpg' then
    raise exception 'an authorized reader should be given the thumbnail path';
  end if;
  if exists (
    select 1 from public.media_visible_to_invite(
      'nobody-hash', '00000000-0000-0000-0000-00000000e002', 'k1')
  ) then
    raise exception 'an unknown token must still be refused the thumbnail';
  end if;
end $$;

select 'media_thumbnails.sql: all checks passed' as result;

rollback;
