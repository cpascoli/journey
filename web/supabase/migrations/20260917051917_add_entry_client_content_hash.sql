alter table public.entries
  add column client_content_hash text
  check (client_content_hash ~ '^[0-9a-f]{64}$');

-- The payload hash changes in the same transaction as every entry field and
-- tag. Older clients omit it, which deliberately clears any previous hash.
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
      visibility, revision, client_content_hash
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
      1,
      p_fields->>'client_content_hash'
    );
    next_revision := 1;
    was_created := true;
  else
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
      revision = next_revision,
      client_content_hash = p_fields->>'client_content_hash'
    where e.id = p_id;
    was_created := false;
  end if;

  delete from public.entry_tags et
  where et.entry_id = p_id and not (et.tag_id = any (p_tag_ids));

  insert into public.entry_tags (entry_id, tag_id)
    select p_id, t from unnest(p_tag_ids) as t
  on conflict do nothing;

  saved_revision := next_revision;
  return next;
end;
$$;

revoke execute on function public.save_entry(uuid, jsonb, uuid[]) from public, anon, authenticated;
grant execute on function public.save_entry(uuid, jsonb, uuid[]) to service_role;
