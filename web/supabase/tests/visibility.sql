-- The all-tags rule in SQL (public.entries_visible_to_invite) must agree with
-- isVisibleToInvite in web/src/lib/domain/visibility.ts, case for case.
-- Also checks that a tag still used by entries can't be deleted, and that
-- removing a tag from an invite is allowed (it only narrows access).
--
-- Run against a database with the migrations applied, never production:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/visibility.sql
-- Everything runs in a transaction that is rolled back.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family'),
  ('00000000-0000-0000-0000-00000000f002', 'Sport'),
  ('00000000-0000-0000-0000-00000000f003', 'Dating');

insert into public.entries (id, occurred_at, day, visibility) values
  ('00000000-0000-0000-0000-00000000e001', now(), current_date, 'shared'),  -- untagged
  ('00000000-0000-0000-0000-00000000e002', now(), current_date, 'private'), -- private, untagged
  ('00000000-0000-0000-0000-00000000e003', now(), current_date, 'shared'),  -- sport
  ('00000000-0000-0000-0000-00000000e004', now(), current_date, 'shared');  -- dating + sport

insert into public.entry_tags (entry_id, tag_id) values
  ('00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-00000000f003'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-00000000f002');

insert into public.invites (id, name, token_hash, revoked_at) values
  ('00000000-0000-0000-0000-00000000a001', 'No tags', 'hash-a001', null),
  ('00000000-0000-0000-0000-00000000a002', 'Sport', 'hash-a002', null),
  ('00000000-0000-0000-0000-00000000a003', 'Sport, dating, family', 'hash-a003', null),
  ('00000000-0000-0000-0000-00000000a004', 'Revoked', 'hash-a004', now());

insert into public.invite_tags (invite_id, tag_id) values
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000f003'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-00000000f003');

-- The last four characters of each visible entry id, in order.
create function pg_temp.visible(p_invite uuid) returns text
language sql as $$
  select coalesce(string_agg(right(id::text, 4), ',' order by id), '')
  from public.entries_visible_to_invite(p_invite)
$$;

do $$
declare
  got text;
begin
  got := pg_temp.visible('00000000-0000-0000-0000-00000000a001');
  if got <> 'e001' then
    raise exception 'an invite with no tags should see only untagged shared entries, saw "%"', got;
  end if;

  got := pg_temp.visible('00000000-0000-0000-0000-00000000a002');
  if got <> 'e001,e003' then
    raise exception 'a sport invite should not see the dating+sport entry, saw "%"', got;
  end if;

  got := pg_temp.visible('00000000-0000-0000-0000-00000000a003');
  if got <> 'e001,e003,e004' then
    raise exception 'an invite with every tag should see all shared entries, saw "%"', got;
  end if;

  got := pg_temp.visible('00000000-0000-0000-0000-00000000a004');
  if got <> '' then
    raise exception 'a revoked invite should see nothing, saw "%"', got;
  end if;
end $$;

-- Deleting a tag that entries use would leave them untagged, i.e. visible to
-- every invite, so the database must refuse.
do $$
begin
  begin
    delete from public.tags where id = '00000000-0000-0000-0000-00000000f002';
    raise exception 'deleting a tag that entries use should fail';
  exception
    when foreign_key_violation then null;
  end;
end $$;

-- Family is only on an invite: deleting it just narrows that invite.
delete from public.tags where id = '00000000-0000-0000-0000-00000000f001';

do $$
begin
  if exists (
    select 1 from public.invite_tags where tag_id = '00000000-0000-0000-0000-00000000f001'
  ) then
    raise exception 'removing a tag should cascade off invites';
  end if;
end $$;

select 'visibility.sql: all checks passed' as result;

rollback;
