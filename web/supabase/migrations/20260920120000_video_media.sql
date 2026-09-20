-- Videos alongside photos. Entry media already has a `kind` enum and a
-- kind-agnostic shape; what it lacked was a way to record a video's duration
-- and content type, and a commit function that writes anything but 'photo'.
--
-- Videos live in Cloudflare R2, not Supabase Storage: a minute of 720p is
-- ~19 MB, and R2 charges no egress. The object store is encoded in
-- `storage_path` as an `r2:` prefix rather than a separate column. The durable
-- `storage_cleanup_queue` keys on the path alone, so a second column could
-- disagree with it and send a delete to the wrong store; one opaque string
-- cannot.

alter table public.entry_media
  add column if not exists content_type text,
  add column if not exists duration_seconds numeric;

-- commit_media_upload hardcodes 'photo' and has no place for duration or
-- content type. Its signature is part of an applied migration, so this is a
-- new function rather than an edit; the photo route moves over to it too.
-- The locking, the cleanup-queue claim and the replaced-path return are
-- unchanged from 20260917053253_atomic_media_lifecycle.sql: that ordering is
-- what stops a cleanup worker racing an upload into a dangling media row.
create or replace function public.commit_media_upload_v2(
  p_entry_id uuid,
  p_asset_key text,
  p_storage_path text,
  p_kind public.media_kind,
  p_content_type text,
  p_width integer,
  p_height integer,
  p_duration_seconds numeric,
  p_taken_at timestamptz,
  p_sort_order integer
)
returns table (replaced_storage_path text)
language plpgsql
set search_path = ''
as $$
declare
  old_path text;
  released_path text;
begin
  -- Serialize uploads, entry saves, and deletion for this entry.
  perform 1 from public.entries e where e.id = p_entry_id for update;
  if not found then
    raise foreign_key_violation using message = 'entry does not exist';
  end if;

  -- A cleanup worker that claimed this path won the race. Keep the previous
  -- media row intact rather than referencing an object being removed.
  delete from public.storage_cleanup_queue q
  where q.storage_path = p_storage_path
    and q.claimed_at is null
  returning q.storage_path into released_path;
  if released_path is null then
    raise exception using errcode = '55000', message = 'upload path is not available';
  end if;

  select em.storage_path into old_path
  from public.entry_media em
  where em.entry_id = p_entry_id and em.asset_key = p_asset_key
  for update;

  insert into public.entry_media (
    entry_id, asset_key, kind, storage_path, content_type,
    width, height, duration_seconds, taken_at, sort_order
  ) values (
    p_entry_id, p_asset_key, p_kind, p_storage_path, p_content_type,
    p_width, p_height, p_duration_seconds, p_taken_at, p_sort_order
  )
  on conflict (entry_id, asset_key) do update set
    kind = excluded.kind,
    storage_path = excluded.storage_path,
    content_type = excluded.content_type,
    width = excluded.width,
    height = excluded.height,
    duration_seconds = excluded.duration_seconds,
    taken_at = excluded.taken_at,
    sort_order = excluded.sort_order;

  if old_path is not null and old_path <> p_storage_path then
    insert into public.storage_cleanup_queue (storage_path)
    values (old_path)
    on conflict (storage_path) do nothing;
    replaced_storage_path := old_path;
  else
    replaced_storage_path := null;
  end if;
  return next;
end;
$$;

revoke execute on function public.commit_media_upload_v2(
  uuid, text, text, public.media_kind, text, integer, integer, numeric, timestamptz, integer
) from public, anon, authenticated;

grant execute on function public.commit_media_upload_v2(
  uuid, text, text, public.media_kind, text, integer, integer, numeric, timestamptz, integer
) to service_role;
