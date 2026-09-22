-- Lets the owner correct an entry's text from the dashboard.
--
-- Deliberately narrow: this touches only the text columns. Tags and
-- visibility decide who may read an entry, and they go through save_entry
-- for a reason, so a text edit must not be able to reach them even by
-- mistake. There is no path here to widen access.
--
-- The app remains the source of truth. A correction here bumps `revision`,
-- so any narrative proposal written against the old text becomes stale, and
-- clears `client_content_hash`, because what the website holds is no longer
-- what the app last sent — leaving the old hash in place would assert a match
-- that is no longer true.
create or replace function public.save_entry_text(
  p_id uuid,
  p_title text,
  p_notes text,
  p_narrative text,
  p_translation_language text,
  p_translated_title text,
  p_translated_notes text,
  p_translated_narrative text
)
returns table (saved boolean, new_revision integer)
language plpgsql
set search_path = ''
as $$
begin
  -- Locks the entry so this cannot interleave with a publish from the app.
  perform 1 from public.entries e where e.id = p_id for update;
  if not found then
    saved := false;
    new_revision := 0;
    return next;
    return;
  end if;

  update public.entries e
  set title = coalesce(p_title, ''),
      notes = coalesce(p_notes, ''),
      narrative = coalesce(p_narrative, ''),
      translation_language = coalesce(p_translation_language, ''),
      translated_title = coalesce(p_translated_title, ''),
      translated_notes = coalesce(p_translated_notes, ''),
      translated_narrative = coalesce(p_translated_narrative, ''),
      -- An edit from the website is the owner's own words, not the app's.
      narrative_source = 'user',
      revision = e.revision + 1,
      client_content_hash = null
  where e.id = p_id
  returning e.revision into new_revision;

  saved := true;
  return next;
end;
$$;

revoke execute on function public.save_entry_text(
  uuid, text, text, text, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.save_entry_text(
  uuid, text, text, text, text, text, text, text
) to service_role;
