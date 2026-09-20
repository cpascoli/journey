-- Exact invite/media authorization and service-role-only cleanup queue.
-- Run only against the local stack with all migrations applied.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family'),
  ('00000000-0000-0000-0000-00000000f002', 'Sport');

insert into public.entries (id, occurred_at, day, visibility) values
  ('00000000-0000-0000-0000-00000000e001', now(), current_date, 'shared'),
  ('00000000-0000-0000-0000-00000000e002', now(), current_date, 'shared'),
  ('00000000-0000-0000-0000-00000000e003', now(), current_date, 'private');

insert into public.entry_tags (entry_id, tag_id) values
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-00000000f001');

insert into public.entry_media (entry_id, asset_key, kind, storage_path) values
  ('00000000-0000-0000-0000-00000000e001', 'photo', 'photo', 'entries/e001/photo.jpg'),
  ('00000000-0000-0000-0000-00000000e002', 'photo', 'photo', 'entries/e002/photo.jpg'),
  ('00000000-0000-0000-0000-00000000e003', 'photo', 'photo', 'entries/e003/photo.jpg');

insert into public.invites (id, name, token_hash, revoked_at) values
  ('00000000-0000-0000-0000-00000000a001', 'Family', 'family-hash', null),
  ('00000000-0000-0000-0000-00000000a002', 'Sport', 'sport-hash', null),
  ('00000000-0000-0000-0000-00000000a003', 'Revoked', 'revoked-hash', now());

insert into public.invite_tags (invite_id, tag_id) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000f001');

do $$
begin
  if (select count(*) from public.media_visible_to_invite(
    'family-hash', '00000000-0000-0000-0000-00000000e002', 'photo'
  )) <> 1 then
    raise exception 'fully tagged invite should see exact shared media';
  end if;
  if (select count(*) from public.media_visible_to_invite(
    'sport-hash', '00000000-0000-0000-0000-00000000e002', 'photo'
  )) <> 0 then
    raise exception 'under-tagged invite must not see media';
  end if;
  if (select count(*) from public.media_visible_to_invite(
    'family-hash', '00000000-0000-0000-0000-00000000e003', 'photo'
  )) <> 0 then
    raise exception 'private entry media must not be visible to invites';
  end if;
  if (select count(*) from public.media_visible_to_invite(
    'revoked-hash', '00000000-0000-0000-0000-00000000e002', 'photo'
  )) <> 0 then
    raise exception 'revoked invite must not see media';
  end if;
  if (select count(*) from public.media_visible_to_invite(
    'family-hash', '00000000-0000-0000-0000-00000000e002', 'missing'
  )) <> 0 then
    raise exception 'missing media must not produce a row';
  end if;
end $$;

do $$
declare
  committed record;
  removed record;
  deleted_entry record;
begin
  if not public.prepare_media_upload(
    '00000000-0000-0000-0000-00000000e001',
    'entries/e001/photo/version-2.jpg'
  ) then
    raise exception 'known entry upload should be prepared';
  end if;
  if public.prepare_media_upload(
    '00000000-0000-0000-0000-00000000e099',
    'entries/e099/photo/version-1.jpg'
  ) then
    raise exception 'unknown entry upload must not be prepared';
  end if;

  select * into committed from public.commit_media_upload(
    '00000000-0000-0000-0000-00000000e001',
    'photo',
    'entries/e001/photo/version-2.jpg',
    1200,
    800,
    now(),
    3
  );
  if committed.replaced_storage_path <> 'entries/e001/photo.jpg'
     or (select storage_path from public.entry_media
         where entry_id = '00000000-0000-0000-0000-00000000e001'
           and asset_key = 'photo') <> 'entries/e001/photo/version-2.jpg'
     or exists (
       select 1 from public.storage_cleanup_queue
       where storage_path = 'entries/e001/photo/version-2.jpg'
     )
     or not exists (
       select 1 from public.storage_cleanup_queue
       where storage_path = 'entries/e001/photo.jpg'
     ) then
    raise exception 'upload commit did not atomically swap and queue paths';
  end if;

  select * into removed from public.delete_entry_media(
    '00000000-0000-0000-0000-00000000e001',
    'photo'
  );
  if not removed.deleted
     or removed.cleanup_paths <> array['entries/e001/photo/version-2.jpg']::text[]
     or exists (
       select 1 from public.entry_media
       where entry_id = '00000000-0000-0000-0000-00000000e001'
     )
     or not exists (
       select 1 from public.storage_cleanup_queue
       where storage_path = 'entries/e001/photo/version-2.jpg'
     ) then
    raise exception 'individual delete did not atomically remove and queue media';
  end if;

  select * into deleted_entry from public.delete_entry_with_media(
    '00000000-0000-0000-0000-00000000e003'
  );
  if not deleted_entry.deleted
     or deleted_entry.cleanup_paths <> array['entries/e003/photo.jpg']::text[]
     or exists (
       select 1 from public.entries
       where id = '00000000-0000-0000-0000-00000000e003'
     )
     or not exists (
       select 1 from public.storage_cleanup_queue
       where storage_path = 'entries/e003/photo.jpg'
     ) then
    raise exception 'entry delete did not atomically remove and queue media';
  end if;
end $$;

-- Reconciliation claims only old, currently unreferenced paths.
do $$
declare
  claimed record;
begin
  insert into public.storage_cleanup_queue (storage_path, created_at) values
    ('entries/e002/photo.jpg', now() - interval '1 hour'),
    ('entries/orphan.jpg', now() - interval '1 hour')
  on conflict (storage_path) do update
    set created_at = excluded.created_at;

  select * into claimed from public.claim_storage_cleanup(10)
  where storage_path = 'entries/orphan.jpg';
  if claimed.storage_path is null then
    raise exception 'unreferenced path should be claimable';
  end if;
  if (select claimed_at from public.storage_cleanup_queue
      where storage_path = 'entries/e002/photo.jpg') is not null then
    raise exception 'currently referenced path must never be claimed';
  end if;

  perform public.finish_storage_cleanup('entries/orphan.jpg', false, 'offline');
  if (select attempts from public.storage_cleanup_queue
      where storage_path = 'entries/orphan.jpg') <> 1
     or (select claimed_at from public.storage_cleanup_queue
         where storage_path = 'entries/orphan.jpg') is not null then
    raise exception 'failed cleanup should remain queued and be released';
  end if;
  perform public.finish_storage_cleanup('entries/orphan.jpg', true, null);
  if exists (
    select 1 from public.storage_cleanup_queue
    where storage_path = 'entries/orphan.jpg'
  ) then
    raise exception 'successful cleanup should clear its queue row';
  end if;
end $$;

do $$
begin
  if has_table_privilege('anon', 'public.storage_cleanup_queue', 'select')
     or has_table_privilege('authenticated', 'public.storage_cleanup_queue', 'select')
     or not has_table_privilege('service_role', 'public.storage_cleanup_queue', 'select,insert,update,delete') then
    raise exception 'cleanup queue privileges are not service-role-only';
  end if;
  if has_function_privilege(
    'anon',
    'public.media_visible_to_invite(text,uuid,text)',
    'execute'
  ) then
    raise exception 'anon must not execute media authorization';
  end if;
  if has_function_privilege(
    'anon',
    'public.commit_media_upload(uuid,text,text,integer,integer,timestamptz,integer)',
    'execute'
  ) then
    raise exception 'anon must not execute media writes';
  end if;
end $$;

select 'secure_media.sql: all checks passed' as result;

rollback;
