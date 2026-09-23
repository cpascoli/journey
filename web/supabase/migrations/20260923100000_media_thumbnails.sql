-- A small copy of each photo, so a grid of ten does not mean ten full-size
-- downloads. The original is still what the viewer opens.
--
-- Cleanup is a trigger rather than new versions of the four functions that
-- already return cleanup paths: a thumbnail's lifetime is exactly its media
-- row's, so queueing it whenever that row loses it keeps every existing
-- deletion path correct without touching any of them.

alter table public.entry_media
  add column if not exists thumb_path text;

create or replace function public.queue_replaced_thumbnail()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.thumb_path is not null then
      insert into public.storage_cleanup_queue (storage_path)
      values (old.thumb_path)
      on conflict (storage_path) do nothing;
    end if;
    return old;
  end if;

  -- Replaced by a different object, so the old one is now unreferenced.
  if old.thumb_path is not null and old.thumb_path is distinct from new.thumb_path then
    insert into public.storage_cleanup_queue (storage_path)
    values (old.thumb_path)
    on conflict (storage_path) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists entry_media_queue_thumbnail_cleanup on public.entry_media;
create trigger entry_media_queue_thumbnail_cleanup
  after update or delete on public.entry_media
  for each row execute function public.queue_replaced_thumbnail();

-- Records an uploaded thumbnail against media that already exists. Returns
-- nothing when the media row is gone, so a thumbnail can never resurrect one.
create or replace function public.commit_media_thumbnail(
  p_entry_id uuid,
  p_asset_key text,
  p_thumb_path text
)
returns table (committed boolean)
language plpgsql
set search_path = ''
as $$
declare
  released_path text;
begin
  perform 1 from public.entries e where e.id = p_entry_id for update;
  if not found then
    committed := false;
    return next;
    return;
  end if;

  -- Same race guard as commit_media_upload_v2: a cleanup worker that claimed
  -- this path has won, and the row must not point at an object being removed.
  delete from public.storage_cleanup_queue q
  where q.storage_path = p_thumb_path
    and q.claimed_at is null
  returning q.storage_path into released_path;
  if released_path is null then
    raise exception using errcode = '55000', message = 'upload path is not available';
  end if;

  update public.entry_media em
  set thumb_path = p_thumb_path
  where em.entry_id = p_entry_id and em.asset_key = p_asset_key;

  committed := found;
  return next;
end;
$$;

revoke execute on function public.queue_replaced_thumbnail() from public, anon, authenticated;
revoke execute on function public.commit_media_thumbnail(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.commit_media_thumbnail(uuid, text, text) to service_role;

-- Media authorization already returns the object path; it now also says
-- where the small copy is, so one query answers both. Keeping it as one
-- function matters more than avoiding the drop: the all-tags rule living in
-- two places is exactly the hazard this schema warns about.
--
-- Widening the result is backward compatible — the deployed reader selects
-- storage_path by name — so the order of migration and deploy does not
-- matter here. A return type cannot be changed in place, hence the drop.
drop function if exists public.media_visible_to_invite(text, uuid, text);

create function public.media_visible_to_invite(
  p_token_hash text,
  p_entry_id uuid,
  p_asset_key text
)
returns table (storage_path text, thumb_path text)
language sql
stable
set search_path = ''
as $$
  select em.storage_path, em.thumb_path
  from public.invites i
  join public.entries e on e.id = p_entry_id
  join public.entry_media em
    on em.entry_id = e.id and em.asset_key = p_asset_key
  where i.token_hash = p_token_hash
    and i.revoked_at is null
    and e.visibility = 'shared'
    and not exists (
      select 1
      from public.entry_tags et
      where et.entry_id = e.id
        and not exists (
          select 1
          from public.invite_tags it
          where it.invite_id = i.id
            and it.tag_id = et.tag_id
        )
    );
$$;

revoke execute on function public.media_visible_to_invite(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.media_visible_to_invite(text, uuid, text)
  to service_role;
