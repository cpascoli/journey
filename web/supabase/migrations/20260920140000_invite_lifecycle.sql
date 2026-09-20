-- Managing an invite after it exists: changing which tags it may read, and
-- replacing its link.
--
-- An invite's tags were fixed at creation, so a tag created later was
-- invisible to everyone already invited, with no way to grant it.

-- The whole tag set is written in one statement, never insert-then-delete:
-- the same reason entry tags go through save_entry. A half-applied change
-- would briefly leave an invite able to read more than intended, and "briefly"
-- is enough when the reader is polling.
create or replace function public.set_invite_tags(
  p_invite_id uuid,
  p_tag_ids uuid[]
)
returns table (updated boolean, tag_ids uuid[])
language plpgsql
set search_path = ''
as $$
begin
  -- Locks the invite so a concurrent change cannot interleave with this one.
  perform 1 from public.invites i where i.id = p_invite_id for update;
  if not found then
    updated := false;
    tag_ids := array[]::uuid[];
    return next;
    return;
  end if;

  delete from public.invite_tags it
  where it.invite_id = p_invite_id
    and not (it.tag_id = any(p_tag_ids));

  insert into public.invite_tags (invite_id, tag_id)
  select p_invite_id, t from unnest(p_tag_ids) as t
  on conflict do nothing;

  select coalesce(array_agg(it.tag_id order by it.tag_id), array[]::uuid[])
    into tag_ids
  from public.invite_tags it
  where it.invite_id = p_invite_id;

  updated := true;
  return next;
end;
$$;

-- Replacing the token invalidates the old link in the same statement that
-- issues the new one: there is never a moment when both work. A revoked
-- invite keeps its revocation — rotating must not quietly restore access.
create or replace function public.rotate_invite_token(
  p_invite_id uuid,
  p_token_hash text
)
returns table (rotated boolean)
language plpgsql
set search_path = ''
as $$
begin
  update public.invites i
  set token_hash = p_token_hash,
      last_seen_at = null
  where i.id = p_invite_id
    and i.revoked_at is null;

  rotated := found;
  return next;
end;
$$;

-- How many entries an invite can actually read. The all-tags rule is subtle
-- and the failure mode is over-sharing, so the app shows this before anyone
-- sends a link.
create or replace function public.invite_visible_entry_count(p_invite_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer from public.entries_visible_to_invite(p_invite_id);
$$;

-- A reader's visit should update last_seen_at, but not once per request.
create or replace function public.touch_invite_seen(
  p_invite_id uuid,
  p_not_before interval default interval '1 hour'
)
returns void
language sql
set search_path = ''
as $$
  update public.invites i
  set last_seen_at = timezone('utc', now())
  where i.id = p_invite_id
    and (i.last_seen_at is null or i.last_seen_at < timezone('utc', now()) - p_not_before);
$$;

revoke execute on function public.set_invite_tags(uuid, uuid[])
  from public, anon, authenticated;
revoke execute on function public.rotate_invite_token(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.invite_visible_entry_count(uuid)
  from public, anon, authenticated;
revoke execute on function public.touch_invite_seen(uuid, interval)
  from public, anon, authenticated;

grant execute on function public.set_invite_tags(uuid, uuid[]) to service_role;
grant execute on function public.rotate_invite_token(uuid, text) to service_role;
grant execute on function public.invite_visible_entry_count(uuid) to service_role;
grant execute on function public.touch_invite_seen(uuid, interval) to service_role;
