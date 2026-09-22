-- Editing an entry's text from the dashboard: what it changes, and more
-- importantly what it must not.
-- Run only against the local stack with all migrations applied.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family');

insert into public.entries (
  id, occurred_at, day, title, notes, narrative, visibility,
  translation_language, translated_title, translated_narrative,
  narrative_source, client_content_hash
) values (
  '00000000-0000-0000-0000-00000000e001', now(), current_date,
  'Temple of Dawn', 'Private notes', 'The story in English', 'shared',
  'it', 'Tempio dell''Alba', 'La storia in italiano',
  'chatgpt', repeat('a', 64)
);

insert into public.entry_tags (entry_id, tag_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000f001');

do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  before_revision integer;
  result record;
  row_after record;
begin
  select e.revision into before_revision from public.entries e where e.id = v_entry;

  select * into result from public.save_entry_text(
    v_entry, 'Temple of Dawn, corrected', 'Private notes', 'The corrected story',
    'it', 'Tempio dell''Alba, corretto', 'Private notes', 'La storia corretta'
  );
  if not result.saved then
    raise exception 'saving an existing entry should succeed';
  end if;

  select * into row_after from public.entries e where e.id = v_entry;
  if row_after.title <> 'Temple of Dawn, corrected'
     or row_after.narrative <> 'The corrected story' then
    raise exception 'the original text should be updated';
  end if;
  if row_after.translated_title <> 'Tempio dell''Alba, corretto'
     or row_after.translated_narrative <> 'La storia corretta' then
    raise exception 'the translation should be updated';
  end if;

  -- A proposal written against the old text must become stale.
  if row_after.revision <> before_revision + 1 or result.new_revision <> row_after.revision then
    raise exception 'the revision should advance, got %', row_after.revision;
  end if;
  -- The website no longer holds what the app last sent, and must not claim to.
  if row_after.client_content_hash is not null then
    raise exception 'the content hash must be cleared, not left asserting a stale match';
  end if;
  -- An edit from the dashboard is the owner's own words.
  if row_after.narrative_source <> 'user' then
    raise exception 'the narrative source should become user, got %', row_after.narrative_source;
  end if;
end $$;

-- The property that matters: text editing cannot change who may read it.
do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  tags_before text;
  visibility_before public.entry_visibility;
begin
  select coalesce(string_agg(et.tag_id::text, ',' order by et.tag_id), '')
    into tags_before
  from public.entry_tags et where et.entry_id = v_entry;
  select e.visibility into visibility_before from public.entries e where e.id = v_entry;

  perform public.save_entry_text(v_entry, 'x', 'x', 'x', '', '', '', '');

  if (select coalesce(string_agg(et.tag_id::text, ',' order by et.tag_id), '')
      from public.entry_tags et where et.entry_id = v_entry) <> tags_before then
    raise exception 'a text edit must not change the entry tags';
  end if;
  if (select e.visibility from public.entries e where e.id = v_entry) <> visibility_before then
    raise exception 'a text edit must not change the entry visibility';
  end if;
end $$;

-- Clearing the translation is allowed, and leaves the original alone.
do $$
declare
  v_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  row_after record;
begin
  perform public.save_entry_text(v_entry, 'Kept', 'Kept notes', 'Kept story', '', '', '', '');
  select * into row_after from public.entries e where e.id = v_entry;
  if row_after.translation_language <> '' or row_after.translated_narrative <> '' then
    raise exception 'the translation should be clearable';
  end if;
  if row_after.narrative <> 'Kept story' then
    raise exception 'clearing the translation must not touch the original';
  end if;
end $$;

-- A missing entry is reported rather than silently created.
do $$
declare
  result record;
begin
  select * into result from public.save_entry_text(
    '00000000-0000-0000-0000-0000000000ff', 'x', '', '', '', '', '', ''
  );
  if result.saved then
    raise exception 'editing a missing entry must not report success';
  end if;
  if (select count(*) from public.entries e
      where e.id = '00000000-0000-0000-0000-0000000000ff') <> 0 then
    raise exception 'editing a missing entry must not insert one';
  end if;
end $$;

-- Service-role only, like every other write.
do $$
declare
  signature constant text :=
    'public.save_entry_text(uuid,text,text,text,text,text,text,text)';
begin
  if has_function_privilege('anon', signature, 'execute')
    or has_function_privilege('authenticated', signature, 'execute') then
    raise exception 'public roles must not edit entry text';
  end if;
  if not has_function_privilege('service_role', signature, 'execute') then
    raise exception 'service_role must edit entry text';
  end if;
end $$;

select 'edit_entry_text.sql: all checks passed' as result;

rollback;
