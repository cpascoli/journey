-- The owner API's atomic writes: save_entry's revision and tag rules, and
-- create_invite. Run against a database with the migrations applied, never
-- production:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/owner_api.sql
-- Everything runs in a transaction that is rolled back.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family'),
  ('00000000-0000-0000-0000-00000000f002', 'Sport');

create function pg_temp.fields(title text, visibility text default 'private') returns jsonb
language sql as $$
  select jsonb_build_object(
    'journal_name', 'Main', 'occurred_at', '2026-09-11T09:00:00Z', 'day', '2026-09-11',
    'title', title, 'notes', 'Notes', 'narrative', '', 'narrative_source', 'user',
    'place_name', 'Bangkok', 'latitude', 13.7, 'longitude', 100.5, 'location_precision', 'city',
    'translation_language', '', 'translated_title', '', 'translated_notes', '',
    'translated_narrative', '', 'visibility', visibility)
$$;

create function pg_temp.tags_of(p_entry uuid) returns text
language sql as $$
  select coalesce(string_agg(right(tag_id::text, 4), ',' order by tag_id), '')
  from public.entry_tags where entry_id = p_entry
$$;

do $$
declare
  entry_id constant uuid := '00000000-0000-0000-0000-00000000e001';
  result record;
begin
  select * into result from public.save_entry(entry_id, pg_temp.fields('Temple of Dawn'),
    array['00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000f002']::uuid[]);
  if result.saved_revision <> 1 or not result.was_created then
    raise exception 'a new entry should be created at revision 1, got % / %', result.saved_revision, result.was_created;
  end if;
  if pg_temp.tags_of(entry_id) <> 'f001,f002' then
    raise exception 'new entry tags wrong: %', pg_temp.tags_of(entry_id);
  end if;

  -- Same text, fewer tags, shared: revision stays, tags are replaced.
  select * into result from public.save_entry(entry_id, pg_temp.fields('Temple of Dawn', 'shared'),
    array['00000000-0000-0000-0000-00000000f002']::uuid[]);
  if result.saved_revision <> 1 or result.was_created then
    raise exception 'a tag-only change should keep revision 1, got %', result.saved_revision;
  end if;
  if pg_temp.tags_of(entry_id) <> 'f002' then
    raise exception 'tags should be replaced, got %', pg_temp.tags_of(entry_id);
  end if;
  if (select visibility from public.entries where id = entry_id) <> 'shared' then
    raise exception 'visibility should be updated';
  end if;

  -- New title: revision moves.
  select * into result from public.save_entry(entry_id, pg_temp.fields('Temple of Dawn at sunrise', 'shared'),
    array['00000000-0000-0000-0000-00000000f002']::uuid[]);
  if result.saved_revision <> 2 then
    raise exception 'a text change should bump the revision to 2, got %', result.saved_revision;
  end if;

  -- No tags at all clears them.
  perform public.save_entry(entry_id, pg_temp.fields('Temple of Dawn at sunrise', 'shared'), array[]::uuid[]);
  if pg_temp.tags_of(entry_id) <> '' then
    raise exception 'an empty tag list should clear the tags, got %', pg_temp.tags_of(entry_id);
  end if;
end $$;

-- An unknown tag fails the whole save: the entry keeps its old tags and text.
do $$
declare
  entry_id constant uuid := '00000000-0000-0000-0000-00000000e002';
begin
  perform public.save_entry(entry_id, pg_temp.fields('Before'),
    array['00000000-0000-0000-0000-00000000f001']::uuid[]);
  begin
    perform public.save_entry(entry_id, pg_temp.fields('After'),
      array['00000000-0000-0000-0000-0000000000ff']::uuid[]);
    raise exception 'saving with an unknown tag should fail';
  exception
    when foreign_key_violation then null;
  end;
  if (select title from public.entries where id = entry_id) <> 'Before'
     or pg_temp.tags_of(entry_id) <> 'f001' then
    raise exception 'a failed save must leave the entry untouched';
  end if;
end $$;

do $$
declare
  created record;
  tag_count integer;
begin
  select * into created from public.create_invite('Sport friends', 'hash-sport',
    array['00000000-0000-0000-0000-00000000f002']::uuid[]);
  select count(*) into tag_count from public.invite_tags where invite_id = created.new_invite_id;
  if created.new_invite_id is null or tag_count <> 1 then
    raise exception 'create_invite should return the invite with its tag, got % tags', tag_count;
  end if;
end $$;

-- The public roles can't call the write functions.
do $$
begin
  set local role anon;
  begin
    perform public.save_entry('00000000-0000-0000-0000-00000000e003', pg_temp.fields('x'), array[]::uuid[]);
    raise exception 'anon must not be able to save entries';
  exception
    when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 'owner_api.sql: all checks passed' as result;

rollback;
