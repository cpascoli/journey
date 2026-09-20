-- Changing an invite's tags and replacing its link.
-- Run only against the local stack with all migrations applied.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family'),
  ('00000000-0000-0000-0000-00000000f002', 'Sport'),
  ('00000000-0000-0000-0000-00000000f003', 'Work');

insert into public.entries (id, occurred_at, day, visibility) values
  ('00000000-0000-0000-0000-00000000e001', now(), current_date, 'shared'),
  ('00000000-0000-0000-0000-00000000e002', now(), current_date, 'shared');

-- e001 needs Family; e002 needs Family and Sport.
insert into public.entry_tags (entry_id, tag_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-00000000f002');

insert into public.invites (id, name, token_hash) values
  ('00000000-0000-0000-0000-00000000a001', 'Friend', 'first-hash'),
  ('00000000-0000-0000-0000-00000000a002', 'Gone', 'revoked-hash');
update public.invites set revoked_at = now()
  where id = '00000000-0000-0000-0000-00000000a002';

do $$
declare
  v_invite constant uuid := '00000000-0000-0000-0000-00000000a001';
  family constant uuid := '00000000-0000-0000-0000-00000000f001';
  sport constant uuid := '00000000-0000-0000-0000-00000000f002';
  result record;
begin
  -- Granting Family opens e001 only: e002 also needs Sport (the all-tags rule).
  select * into result from public.set_invite_tags(v_invite, array[family]);
  if not result.updated or result.tag_ids <> array[family] then
    raise exception 'setting tags should report the new set, got %', result.tag_ids;
  end if;
  if public.invite_visible_entry_count(v_invite) <> 1 then
    raise exception 'one tag should open exactly one entry, got %',
      public.invite_visible_entry_count(v_invite);
  end if;

  -- Adding Sport opens both.
  perform public.set_invite_tags(v_invite, array[family, sport]);
  if public.invite_visible_entry_count(v_invite) <> 2 then
    raise exception 'both tags should open both entries';
  end if;

  -- Narrowing takes effect immediately, and removes rows rather than adding.
  perform public.set_invite_tags(v_invite, array[sport]);
  if exists (
    select 1 from public.invite_tags it
    where it.invite_id = v_invite and it.tag_id = family
  ) then
    raise exception 'a tag left out of the new set must be removed';
  end if;
  if public.invite_visible_entry_count(v_invite) <> 0 then
    raise exception 'an invite missing a required tag must see nothing';
  end if;

  -- Clearing every tag leaves only untagged entries, of which there are none.
  perform public.set_invite_tags(v_invite, array[]::uuid[]);
  if exists (select 1 from public.invite_tags it where it.invite_id = v_invite) then
    raise exception 'an empty set must clear every tag';
  end if;

  -- An unknown invite is reported, not silently created.
  select * into result
  from public.set_invite_tags('00000000-0000-0000-0000-0000000000ff', array[family]);
  if result.updated then
    raise exception 'setting tags on a missing invite must not report success';
  end if;
end $$;

do $$
declare
  v_invite constant uuid := '00000000-0000-0000-0000-00000000a001';
  revoked constant uuid := '00000000-0000-0000-0000-00000000a002';
begin
  -- Rotating replaces the hash, so the old link stops working at that moment.
  if not (select rotated from public.rotate_invite_token(v_invite, 'second-hash')) then
    raise exception 'rotating an active invite should succeed';
  end if;
  if exists (select 1 from public.invites i where i.token_hash = 'first-hash') then
    raise exception 'the previous token must no longer resolve';
  end if;
  if not exists (
    select 1 from public.invites i
    where i.id = v_invite and i.token_hash = 'second-hash' and i.last_seen_at is null
  ) then
    raise exception 'the new token must be in place, with the visit history cleared';
  end if;

  -- Rotating must not quietly restore a revoked invite.
  if (select rotated from public.rotate_invite_token(revoked, 'third-hash')) then
    raise exception 'a revoked invite must not be rotated';
  end if;
  if exists (select 1 from public.invites i where i.token_hash = 'third-hash') then
    raise exception 'a revoked invite must keep its old hash';
  end if;
end $$;

do $$
declare
  v_invite constant uuid := '00000000-0000-0000-0000-00000000a001';
  first_seen timestamptz;
begin
  perform public.touch_invite_seen(v_invite);
  select i.last_seen_at into first_seen from public.invites i where i.id = v_invite;
  if first_seen is null then
    raise exception 'a first visit must be recorded';
  end if;

  -- Throttled: a second visit within the window must not write again.
  perform public.touch_invite_seen(v_invite);
  if (select i.last_seen_at from public.invites i where i.id = v_invite) <> first_seen then
    raise exception 'visits must not be recorded on every request';
  end if;

  -- Once the window has passed, it updates.
  update public.invites i set last_seen_at = timezone('utc', now()) - interval '2 hours'
  where i.id = v_invite;
  perform public.touch_invite_seen(v_invite);
  if (select i.last_seen_at from public.invites i where i.id = v_invite)
     < timezone('utc', now()) - interval '1 minute' then
    raise exception 'a visit after the window must be recorded';
  end if;
end $$;

-- Invite management stays service-role only.
do $$
declare
  signatures constant text[] := array[
    'public.set_invite_tags(uuid,uuid[])',
    'public.rotate_invite_token(uuid,text)',
    'public.invite_visible_entry_count(uuid)',
    'public.touch_invite_seen(uuid,interval)'
  ];
  signature text;
begin
  foreach signature in array signatures loop
    if has_function_privilege('anon', signature, 'execute')
      or has_function_privilege('authenticated', signature, 'execute') then
      raise exception 'public roles must not execute %', signature;
    end if;
    if not has_function_privilege('service_role', signature, 'execute') then
      raise exception 'service_role must execute %', signature;
    end if;
  end loop;
end $$;

select 'invite_lifecycle.sql: all checks passed' as result;

rollback;
