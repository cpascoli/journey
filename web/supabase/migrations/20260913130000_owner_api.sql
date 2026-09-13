-- Writes the owner API makes atomically. Each function runs in one
-- transaction, so an entry is never left, even briefly, with fewer tags than
-- it had before or will have after a save. A moment with fewer tags would be a
-- moment when more invites could see it.

create or replace function public.save_entry(p_id uuid, p_fields jsonb, p_tag_ids uuid[])
returns table (saved_revision integer, was_created boolean)
language plpgsql
as $$
declare
  current_row public.entries%rowtype;
  next_revision integer;
begin
  select * into current_row from public.entries e where e.id = p_id for update;

  if not found then
    insert into public.entries (
      id, journal_name, occurred_at, day, title, notes, narrative, narrative_source,
      place_name, latitude, longitude, location_precision,
      translation_language, translated_title, translated_notes, translated_narrative,
      visibility, revision
    ) values (
      p_id,
      p_fields->>'journal_name',
      (p_fields->>'occurred_at')::timestamptz,
      (p_fields->>'day')::date,
      p_fields->>'title',
      p_fields->>'notes',
      p_fields->>'narrative',
      (p_fields->>'narrative_source')::public.narrative_source,
      p_fields->>'place_name',
      (p_fields->>'latitude')::double precision,
      (p_fields->>'longitude')::double precision,
      (p_fields->>'location_precision')::public.location_precision,
      p_fields->>'translation_language',
      p_fields->>'translated_title',
      p_fields->>'translated_notes',
      p_fields->>'translated_narrative',
      (p_fields->>'visibility')::public.entry_visibility,
      1
    );
    next_revision := 1;
    was_created := true;
  else
    -- Proposals are written against a revision, so only the text they rewrite
    -- moves it: a change of tags or visibility leaves proposals current.
    next_revision := current_row.revision
      + case
          when (current_row.title, current_row.notes, current_row.narrative)
               is distinct from (p_fields->>'title', p_fields->>'notes', p_fields->>'narrative')
          then 1 else 0
        end;
    update public.entries e set
      journal_name = p_fields->>'journal_name',
      occurred_at = (p_fields->>'occurred_at')::timestamptz,
      day = (p_fields->>'day')::date,
      title = p_fields->>'title',
      notes = p_fields->>'notes',
      narrative = p_fields->>'narrative',
      narrative_source = (p_fields->>'narrative_source')::public.narrative_source,
      place_name = p_fields->>'place_name',
      latitude = (p_fields->>'latitude')::double precision,
      longitude = (p_fields->>'longitude')::double precision,
      location_precision = (p_fields->>'location_precision')::public.location_precision,
      translation_language = p_fields->>'translation_language',
      translated_title = p_fields->>'translated_title',
      translated_notes = p_fields->>'translated_notes',
      translated_narrative = p_fields->>'translated_narrative',
      visibility = (p_fields->>'visibility')::public.entry_visibility,
      revision = next_revision
    where e.id = p_id;
    was_created := false;
  end if;

  delete from public.entry_tags et
  where et.entry_id = p_id and not (et.tag_id = any (p_tag_ids));

  -- An unknown tag id fails the foreign key and rolls the whole save back.
  insert into public.entry_tags (entry_id, tag_id)
  select p_id, t from unnest(p_tag_ids) as t
  on conflict do nothing;

  saved_revision := next_revision;
  return next;
end;
$$;

create or replace function public.create_invite(p_name text, p_token_hash text, p_tag_ids uuid[])
returns table (new_invite_id uuid, new_created_at timestamptz)
language plpgsql
as $$
declare
  inserted_id uuid;
begin
  insert into public.invites (name, token_hash)
  values (p_name, p_token_hash)
  returning id into inserted_id;

  insert into public.invite_tags (invite_id, tag_id)
  select inserted_id, t from unnest(p_tag_ids) as t
  on conflict do nothing;

  return query
    select i.id, i.created_at from public.invites i where i.id = inserted_id;
end;
$$;

revoke execute on function public.save_entry(uuid, jsonb, uuid[]) from public, anon, authenticated;
revoke execute on function public.create_invite(text, text, uuid[]) from public, anon, authenticated;
grant execute on function public.save_entry(uuid, jsonb, uuid[]) to service_role;
grant execute on function public.create_invite(text, text, uuid[]) to service_role;

-- The first migration revoked execute on this from PUBLIC, which is also how
-- service_role would have reached it.
grant execute on function public.entries_visible_to_invite(uuid) to service_role;
