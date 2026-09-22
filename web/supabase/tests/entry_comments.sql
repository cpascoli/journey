-- Comment access: a reader may only see or write comments on an entry their
-- invitation can already read, only in their own thread, and only so often.
-- Run only against the local stack with all migrations applied.

begin;

insert into public.tags (id, name) values
  ('00000000-0000-0000-0000-00000000f001', 'Family'),
  ('00000000-0000-0000-0000-00000000f002', 'Sport');

insert into public.entries (id, occurred_at, day, title, visibility) values
  ('00000000-0000-0000-0000-00000000e001', now(), current_date, 'Family day', 'shared'),
  ('00000000-0000-0000-0000-00000000e002', now(), current_date, 'Both tags', 'shared'),
  ('00000000-0000-0000-0000-00000000e003', now(), current_date, 'Private', 'private');

insert into public.entry_tags (entry_id, tag_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-00000000f002');

insert into public.invites (id, name, token_hash) values
  ('00000000-0000-0000-0000-00000000a001', 'Family', 'family-hash'),
  ('00000000-0000-0000-0000-00000000a002', 'Sport', 'sport-hash'),
  ('00000000-0000-0000-0000-00000000a003', 'Gone', 'revoked-hash');
update public.invites set revoked_at = now()
  where id = '00000000-0000-0000-0000-00000000a003';

insert into public.invite_tags (invite_id, tag_id) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000f002'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000f001');

-- Who may comment where.
do $$
declare
  family_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  both_entry constant uuid := '00000000-0000-0000-0000-00000000e002';
  private_entry constant uuid := '00000000-0000-0000-0000-00000000e003';
begin
  if public.commentable_invite('family-hash', family_entry)
     <> '00000000-0000-0000-0000-00000000a001' then
    raise exception 'a fully tagged invitation should be able to comment';
  end if;
  -- The all-tags rule: this entry needs Sport as well.
  if public.commentable_invite('family-hash', both_entry) is not null then
    raise exception 'an under-tagged invitation must not be able to comment';
  end if;
  if public.commentable_invite('family-hash', private_entry) is not null then
    raise exception 'a private entry must accept no comments';
  end if;
  if public.commentable_invite('revoked-hash', family_entry) is not null then
    raise exception 'a revoked invitation must not be able to comment';
  end if;
  if public.commentable_invite('nonsense-hash', family_entry) is not null then
    raise exception 'an unknown token must not be able to comment';
  end if;
end $$;

-- Posting, refusals, and thread privacy.
do $$
declare
  family_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  both_entry constant uuid := '00000000-0000-0000-0000-00000000e002';
  result record;
begin
  select * into result from public.post_reader_comment('family-hash', family_entry, 'Lovely photo!');
  if result.refusal is not null or result.comment_id is null then
    raise exception 'a permitted comment should be accepted, got %', result.refusal;
  end if;

  select * into result from public.post_reader_comment('family-hash', both_entry, 'Sneaking in');
  if result.refusal is distinct from 'not_readable' then
    raise exception 'commenting on an unreadable entry must be refused, got %', result.refusal;
  end if;

  select * into result from public.post_reader_comment('revoked-hash', family_entry, 'Still here?');
  if result.refusal is distinct from 'not_readable' then
    raise exception 'a revoked invitation must be refused, got %', result.refusal;
  end if;

  select * into result from public.post_reader_comment('family-hash', family_entry, '   ');
  if result.refusal is distinct from 'bad_body' then
    raise exception 'an empty comment must be refused, got %', result.refusal;
  end if;

  select * into result
  from public.post_reader_comment('family-hash', family_entry, repeat('x', 2001));
  if result.refusal is distinct from 'bad_body' then
    raise exception 'an over-long comment must be refused, got %', result.refusal;
  end if;

  if (select count(*) from public.entry_comments) <> 1 then
    raise exception 'only the permitted comment should have been stored';
  end if;
end $$;

-- A thread belongs to one invitation, and nobody else can read it.
do $$
declare
  family_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
begin
  -- Give the Sport invitation access to the same entry, then have it comment.
  insert into public.invite_tags (invite_id, tag_id)
  values ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000f001')
  on conflict do nothing;
  perform public.post_reader_comment('sport-hash', family_entry, 'Sport says hello');

  if (select count(*) from public.comment_thread_for_invite('family-hash', family_entry)) <> 1 then
    raise exception 'an invitation must see only its own thread';
  end if;
  if exists (
    select 1 from public.comment_thread_for_invite('family-hash', family_entry)
    where body = 'Sport says hello'
  ) then
    raise exception 'one invitation must never read another invitation''s comments';
  end if;
  if (select count(*) from public.comment_thread_for_invite('sport-hash', family_entry)) <> 1 then
    raise exception 'the other invitation should see its own comment';
  end if;
  -- Losing access hides the conversation without deleting it.
  delete from public.invite_tags
  where invite_id = '00000000-0000-0000-0000-00000000a002'
    and tag_id = '00000000-0000-0000-0000-00000000f001';
  if (select count(*) from public.comment_thread_for_invite('sport-hash', family_entry)) <> 0 then
    raise exception 'an invitation that lost access must not read its old thread';
  end if;
  if (select count(*) from public.entry_comments where body = 'Sport says hello') <> 1 then
    raise exception 'hiding a thread must not delete it';
  end if;
end $$;

-- The hourly limit bounds what one invite link can do.
do $$
declare
  family_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  result record;
  i integer;
begin
  for i in 1..public.reader_comment_limit() loop
    select * into result from public.post_reader_comment('family-hash', family_entry, 'spam ' || i);
    exit when result.refusal is not null;
  end loop;
  select * into result from public.post_reader_comment('family-hash', family_entry, 'one too many');
  if result.refusal is distinct from 'too_many' then
    raise exception 'the hourly limit should refuse the next comment, got %', result.refusal;
  end if;

  -- Older comments stop counting once the hour has passed.
  update public.entry_comments set created_at = timezone('utc', now()) - interval '2 hours'
  where author = 'reader';
  select * into result from public.post_reader_comment('family-hash', family_entry, 'later that day');
  if result.refusal is not null then
    raise exception 'the limit must be a window, not a total, got %', result.refusal;
  end if;
end $$;

-- The owner's side: inbox counts, replies, seen, delete.
do $$
declare
  family_entry constant uuid := '00000000-0000-0000-0000-00000000e001';
  family_invite constant uuid := '00000000-0000-0000-0000-00000000a001';
  result record;
  thread record;
begin
  select * into thread from public.owner_comment_threads()
  where entry_id = family_entry and invite_id = family_invite;
  if thread.invite_name <> 'Family' or thread.entry_title <> 'Family day' then
    raise exception 'the inbox should name the entry and the invitation';
  end if;
  if thread.unseen_count = 0 then
    raise exception 'reader comments should start unseen';
  end if;

  select * into result from public.post_owner_comment(family_entry, family_invite, 'Thank you!');
  if result.refusal is not null then
    raise exception 'the owner should be able to reply, got %', result.refusal;
  end if;
  -- The owner's own reply is never unseen work for the owner.
  if exists (
    select 1 from public.entry_comments c
    where c.author = 'owner' and not c.seen_by_owner
  ) then
    raise exception 'an owner reply must not count as unseen';
  end if;

  -- A reply cannot start a conversation nobody opened.
  select * into result
  from public.post_owner_comment('00000000-0000-0000-0000-00000000e002', family_invite, 'Hello?');
  if result.refusal is distinct from 'no_thread' then
    raise exception 'replying with no thread must be refused, got %', result.refusal;
  end if;

  if public.mark_thread_seen(family_entry, family_invite) = 0 then
    raise exception 'marking a thread seen should clear something';
  end if;
  select * into thread from public.owner_comment_threads()
  where entry_id = family_entry and invite_id = family_invite;
  if thread.unseen_count <> 0 then
    raise exception 'nothing should remain unseen after marking';
  end if;

  if not public.delete_comment((
    select id from public.entry_comments where author = 'owner' limit 1
  )) then
    raise exception 'the owner should be able to delete a comment';
  end if;
  if public.delete_comment('00000000-0000-0000-0000-0000000000ff') then
    raise exception 'deleting a missing comment must report nothing removed';
  end if;
end $$;

-- Deleting an entry takes its conversations with it.
do $$
begin
  delete from public.entries where id = '00000000-0000-0000-0000-00000000e001';
  if (select count(*) from public.entry_comments
      where entry_id = '00000000-0000-0000-0000-00000000e001') <> 0 then
    raise exception 'unpublishing an entry must remove its comments';
  end if;
end $$;

-- Comments stay service-role only.
do $$
declare
  signatures constant text[] := array[
    'public.commentable_invite(text,uuid)',
    'public.comment_thread_for_invite(text,uuid)',
    'public.post_reader_comment(text,uuid,text)',
    'public.owner_comment_threads()',
    'public.owner_comment_thread(uuid,uuid)',
    'public.post_owner_comment(uuid,uuid,text)',
    'public.mark_thread_seen(uuid,uuid)',
    'public.delete_comment(uuid)'
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
  if has_table_privilege('anon', 'public.entry_comments', 'select') then
    raise exception 'anon must not read comments';
  end if;
end $$;

select 'entry_comments.sql: all checks passed' as result;

rollback;
