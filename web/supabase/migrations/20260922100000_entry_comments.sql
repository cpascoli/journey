-- Comments: one private conversation per invitation, per entry.
--
-- This is the first thing a reader may write. Every rule that governs reading
-- an entry has to govern commenting on it, so the visibility check lives here
-- in SQL beside the all-tags rule rather than in a route handler: a reader may
-- only see or add comments on an entry their invitation can already read, and
-- only ever within their own thread.
--
-- Threads are private per invitation. An invitee never learns who else was
-- invited, and two invitations reading the same entry hold separate
-- conversations with the owner.

create type public.comment_author as enum ('owner', 'reader');

/** Longest a comment may be. Also checked by the API before it gets here. */
create table public.entry_comments (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries (id) on delete cascade,
  -- The conversation: comments are always scoped to one invitation, including
  -- the owner's replies, which is what keeps threads private.
  invite_id uuid not null references public.invites (id) on delete cascade,
  -- Null means the entry as a whole. Reserved for per-photo comments so that
  -- adding them later needs no migration; nothing writes it yet.
  asset_key text,
  author public.comment_author not null,
  body text not null check (length(trim(body)) > 0 and length(body) <= 2000),
  -- Lets the owner see what is new without tracking per-device state.
  seen_by_owner boolean not null default false,
  created_at timestamptz not null default timezone('utc', now())
);

create index entry_comments_thread_idx
  on public.entry_comments (entry_id, invite_id, created_at);
create index entry_comments_unseen_idx
  on public.entry_comments (seen_by_owner) where author = 'reader';

alter table public.entry_comments enable row level security;
revoke all on public.entry_comments from public, anon, authenticated;
grant select, insert, update, delete on public.entry_comments to service_role;

-- The all-tags rule again, for one invitation and one entry. Mirrors
-- media_visible_to_invite; a revoked invitation matches nothing.
create or replace function public.commentable_invite(
  p_token_hash text,
  p_entry_id uuid
)
returns uuid
language sql
stable
set search_path = ''
as $$
  select i.id
  from public.invites i
  join public.entries e on e.id = p_entry_id
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

-- A reader's own thread. Returns nothing at all unless the entry is still
-- readable by that invitation, so losing access hides the conversation too.
create or replace function public.comment_thread_for_invite(
  p_token_hash text,
  p_entry_id uuid
)
returns table (
  id uuid,
  author public.comment_author,
  body text,
  created_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select c.id, c.author, c.body, c.created_at
  from public.entry_comments c
  where c.entry_id = p_entry_id
    and c.invite_id = public.commentable_invite(p_token_hash, p_entry_id)
  order by c.created_at;
$$;

/** How many comments one invitation may add per hour. */
create or replace function public.reader_comment_limit()
returns integer
language sql
immutable
set search_path = ''
as $$ select 20 $$;

-- Adds a reader's comment, or says why not. An invite link is a bearer
-- token, so anyone holding it could post: the hourly limit bounds the damage
-- without needing anything outside the database.
create or replace function public.post_reader_comment(
  p_token_hash text,
  p_entry_id uuid,
  p_body text
)
returns table (comment_id uuid, refusal text)
language plpgsql
set search_path = ''
as $$
declare
  v_invite uuid;
  v_recent integer;
begin
  v_invite := public.commentable_invite(p_token_hash, p_entry_id);
  if v_invite is null then
    comment_id := null;
    refusal := 'not_readable';
    return next;
    return;
  end if;

  if length(trim(p_body)) = 0 or length(p_body) > 2000 then
    comment_id := null;
    refusal := 'bad_body';
    return next;
    return;
  end if;

  select count(*) into v_recent
  from public.entry_comments c
  where c.invite_id = v_invite
    and c.author = 'reader'
    and c.created_at > timezone('utc', now()) - interval '1 hour';
  if v_recent >= public.reader_comment_limit() then
    comment_id := null;
    refusal := 'too_many';
    return next;
    return;
  end if;

  insert into public.entry_comments (entry_id, invite_id, author, body)
  values (p_entry_id, v_invite, 'reader', trim(p_body))
  returning id into comment_id;
  refusal := null;
  return next;
end;
$$;

-- Every thread with something in it, newest activity first, for the owner's
-- inbox. Names the invitation so the owner knows who they are talking to.
create or replace function public.owner_comment_threads()
returns table (
  entry_id uuid,
  entry_title text,
  entry_day date,
  invite_id uuid,
  invite_name text,
  invite_revoked boolean,
  comment_count integer,
  unseen_count integer,
  last_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select
    c.entry_id,
    e.title,
    e.day,
    c.invite_id,
    i.name,
    i.revoked_at is not null,
    count(*)::integer,
    count(*) filter (where c.author = 'reader' and not c.seen_by_owner)::integer,
    max(c.created_at)
  from public.entry_comments c
  join public.entries e on e.id = c.entry_id
  join public.invites i on i.id = c.invite_id
  group by c.entry_id, e.title, e.day, c.invite_id, i.name, i.revoked_at
  order by max(c.created_at) desc;
$$;

create or replace function public.owner_comment_thread(
  p_entry_id uuid,
  p_invite_id uuid
)
returns table (
  id uuid,
  author public.comment_author,
  body text,
  seen_by_owner boolean,
  created_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select c.id, c.author, c.body, c.seen_by_owner, c.created_at
  from public.entry_comments c
  where c.entry_id = p_entry_id and c.invite_id = p_invite_id
  order by c.created_at;
$$;

-- The owner replies inside an existing conversation. Requires the thread to
-- exist, so a reply cannot start a conversation with someone who never wrote.
create or replace function public.post_owner_comment(
  p_entry_id uuid,
  p_invite_id uuid,
  p_body text
)
returns table (comment_id uuid, refusal text)
language plpgsql
set search_path = ''
as $$
begin
  if length(trim(p_body)) = 0 or length(p_body) > 2000 then
    comment_id := null;
    refusal := 'bad_body';
    return next;
    return;
  end if;

  if not exists (
    select 1 from public.entry_comments c
    where c.entry_id = p_entry_id and c.invite_id = p_invite_id
  ) then
    comment_id := null;
    refusal := 'no_thread';
    return next;
    return;
  end if;

  insert into public.entry_comments (entry_id, invite_id, author, body, seen_by_owner)
  values (p_entry_id, p_invite_id, 'owner', trim(p_body), true)
  returning id into comment_id;
  refusal := null;
  return next;
end;
$$;

create or replace function public.mark_thread_seen(
  p_entry_id uuid,
  p_invite_id uuid
)
returns integer
language sql
set search_path = ''
as $$
  with marked as (
    update public.entry_comments c
    set seen_by_owner = true
    where c.entry_id = p_entry_id
      and c.invite_id = p_invite_id
      and c.author = 'reader'
      and not c.seen_by_owner
    returning 1
  )
  select count(*)::integer from marked;
$$;

/** Only the owner deletes, and may delete either side of a conversation. */
create or replace function public.delete_comment(p_id uuid)
returns boolean
language sql
set search_path = ''
as $$
  with removed as (
    delete from public.entry_comments c where c.id = p_id returning 1
  )
  select count(*) > 0 from removed;
$$;

revoke execute on function public.commentable_invite(text, uuid) from public, anon, authenticated;
revoke execute on function public.comment_thread_for_invite(text, uuid) from public, anon, authenticated;
revoke execute on function public.reader_comment_limit() from public, anon, authenticated;
revoke execute on function public.post_reader_comment(text, uuid, text) from public, anon, authenticated;
revoke execute on function public.owner_comment_threads() from public, anon, authenticated;
revoke execute on function public.owner_comment_thread(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.post_owner_comment(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.mark_thread_seen(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.delete_comment(uuid) from public, anon, authenticated;

grant execute on function public.commentable_invite(text, uuid) to service_role;
grant execute on function public.comment_thread_for_invite(text, uuid) to service_role;
grant execute on function public.reader_comment_limit() to service_role;
grant execute on function public.post_reader_comment(text, uuid, text) to service_role;
grant execute on function public.owner_comment_threads() to service_role;
grant execute on function public.owner_comment_thread(uuid, uuid) to service_role;
grant execute on function public.post_owner_comment(uuid, uuid, text) to service_role;
grant execute on function public.mark_thread_seen(uuid, uuid) to service_role;
grant execute on function public.delete_comment(uuid) to service_role;
