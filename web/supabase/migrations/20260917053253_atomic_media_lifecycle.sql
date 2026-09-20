-- Keep every Postgres-side media transition atomic. Storage itself is
-- external to Postgres, so paths are durably queued before an upload and
-- before their last database reference is removed.

alter table public.storage_cleanup_queue
  add column claimed_at timestamptz;

create or replace function public.save_entry_with_media(
  p_id uuid,
  p_fields jsonb,
  p_tag_ids uuid[],
  p_media_keys text[]
)
returns table (
  saved_revision integer,
  was_created boolean,
  missing_media text[],
  cleanup_paths text[]
)
language plpgsql
set search_path = ''
as $$
declare
  saved record;
begin
  -- save_entry locks the entry and writes all fields and the complete tag set.
  select * into saved
  from public.save_entry(p_id, p_fields, p_tag_ids);

  saved_revision := saved.saved_revision;
  was_created := saved.was_created;
  missing_media := array[]::text[];
  cleanup_paths := array[]::text[];

  -- NULL preserves compatibility with clients that do not manage media sets.
  if p_media_keys is not null then
    with removed as (
      delete from public.entry_media em
      where em.entry_id = p_id
        and not (em.asset_key = any(p_media_keys))
      returning em.storage_path
    ),
    queued as (
      insert into public.storage_cleanup_queue (storage_path)
      select r.storage_path from removed r
      on conflict (storage_path) do nothing
      returning storage_path
    )
    select coalesce(array_agg(r.storage_path order by r.storage_path), array[]::text[])
      into cleanup_paths
    from removed r;

    update public.entry_media em
    set sort_order = array_position(p_media_keys, em.asset_key) - 1
    where em.entry_id = p_id
      and em.asset_key = any(p_media_keys)
      and em.sort_order is distinct from array_position(p_media_keys, em.asset_key) - 1;

    select coalesce(array_agg(w.asset_key order by w.ordinality), array[]::text[])
      into missing_media
    from unnest(p_media_keys) with ordinality as w(asset_key, ordinality)
    where not exists (
      select 1
      from public.entry_media em
      where em.entry_id = p_id
        and em.asset_key = w.asset_key
    );
  end if;

  return next;
end;
$$;

create or replace function public.prepare_media_upload(
  p_entry_id uuid,
  p_storage_path text
)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.entries e where e.id = p_entry_id
  ) then
    return false;
  end if;

  insert into public.storage_cleanup_queue (storage_path)
  values (p_storage_path)
  on conflict (storage_path) do nothing;
  return true;
end;
$$;

create or replace function public.commit_media_upload(
  p_entry_id uuid,
  p_asset_key text,
  p_storage_path text,
  p_width integer,
  p_height integer,
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
    entry_id, asset_key, kind, storage_path, width, height, taken_at, sort_order
  ) values (
    p_entry_id, p_asset_key, 'photo', p_storage_path,
    p_width, p_height, p_taken_at, p_sort_order
  )
  on conflict (entry_id, asset_key) do update set
    kind = excluded.kind,
    storage_path = excluded.storage_path,
    width = excluded.width,
    height = excluded.height,
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

create or replace function public.delete_entry_media(
  p_entry_id uuid,
  p_asset_key text
)
returns table (deleted boolean, cleanup_paths text[])
language plpgsql
set search_path = ''
as $$
begin
  perform 1 from public.entries e where e.id = p_entry_id for update;

  with removed as (
    delete from public.entry_media em
    where em.entry_id = p_entry_id and em.asset_key = p_asset_key
    returning em.storage_path
  ),
  queued as (
    insert into public.storage_cleanup_queue (storage_path)
    select r.storage_path from removed r
    on conflict (storage_path) do nothing
    returning storage_path
  )
  select count(*) > 0,
         coalesce(array_agg(r.storage_path), array[]::text[])
    into deleted, cleanup_paths
  from removed r;
  return next;
end;
$$;

create or replace function public.delete_entry_with_media(p_id uuid)
returns table (deleted boolean, cleanup_paths text[])
language plpgsql
set search_path = ''
as $$
begin
  perform 1 from public.entries e where e.id = p_id for update;
  if not found then
    deleted := false;
    cleanup_paths := array[]::text[];
    return next;
    return;
  end if;

  select coalesce(array_agg(em.storage_path order by em.storage_path), array[]::text[])
    into cleanup_paths
  from public.entry_media em
  where em.entry_id = p_id;

  insert into public.storage_cleanup_queue (storage_path)
  select unnest(cleanup_paths)
  on conflict (storage_path) do nothing;

  delete from public.entries e where e.id = p_id;
  deleted := true;
  return next;
end;
$$;

-- Claim only paths with no current reference. A claimed path cannot
-- subsequently be committed by commit_media_upload, preventing cleanup from
-- racing an upload into a dangling media row. Fresh work gets a short grace
-- period so normal upload/commit requests are not needlessly preempted.
create or replace function public.claim_storage_cleanup(p_limit integer default 100)
returns table (storage_path text, attempts integer)
language sql
set search_path = ''
as $$
  with candidates as (
    select q.storage_path
    from public.storage_cleanup_queue q
    where q.created_at < timezone('utc', now()) - interval '5 minutes'
      and (
        q.claimed_at is null
        or q.claimed_at < timezone('utc', now()) - interval '15 minutes'
      )
      and not exists (
        select 1 from public.entry_media em where em.storage_path = q.storage_path
      )
    order by q.created_at
    for update skip locked
    limit greatest(1, least(p_limit, 500))
  )
  update public.storage_cleanup_queue q
  set claimed_at = timezone('utc', now())
  from candidates c
  where q.storage_path = c.storage_path
  returning q.storage_path, q.attempts;
$$;

create or replace function public.finish_storage_cleanup(
  p_storage_path text,
  p_removed boolean,
  p_last_error text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_removed then
    delete from public.storage_cleanup_queue q
    where q.storage_path = p_storage_path;
  else
    update public.storage_cleanup_queue q
    set attempts = q.attempts + 1,
        last_attempt_at = timezone('utc', now()),
        last_error = left(p_last_error, 500),
        claimed_at = null
    where q.storage_path = p_storage_path;
  end if;
end;
$$;

revoke execute on function public.save_entry_with_media(uuid, jsonb, uuid[], text[])
  from public, anon, authenticated;
revoke execute on function public.prepare_media_upload(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.commit_media_upload(uuid, text, text, integer, integer, timestamptz, integer)
  from public, anon, authenticated;
revoke execute on function public.delete_entry_media(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.delete_entry_with_media(uuid)
  from public, anon, authenticated;
revoke execute on function public.claim_storage_cleanup(integer)
  from public, anon, authenticated;
revoke execute on function public.finish_storage_cleanup(text, boolean, text)
  from public, anon, authenticated;

grant execute on function public.save_entry_with_media(uuid, jsonb, uuid[], text[])
  to service_role;
grant execute on function public.prepare_media_upload(uuid, text)
  to service_role;
grant execute on function public.commit_media_upload(uuid, text, text, integer, integer, timestamptz, integer)
  to service_role;
grant execute on function public.delete_entry_media(uuid, text)
  to service_role;
grant execute on function public.delete_entry_with_media(uuid)
  to service_role;
grant execute on function public.claim_storage_cleanup(integer)
  to service_role;
grant execute on function public.finish_storage_cleanup(text, boolean, text)
  to service_role;
