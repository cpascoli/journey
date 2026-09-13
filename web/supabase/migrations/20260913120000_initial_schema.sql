-- Journey website: published journal entries, shared by invite.
--
-- Only the server touches these tables, with the service-role key. RLS is on
-- with no policies, so the anon and authenticated roles see nothing even if a
-- key leaks into a browser.

create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- Tags keep the app's ids, so renaming a tag never changes who can see what.
create table public.tags (
  id uuid primary key,
  name text not null check (length(trim(name)) > 0),
  color text not null default 'blue',
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger tags_set_updated_at
  before update on public.tags
  for each row execute function public.set_updated_at();

create type public.entry_visibility as enum ('private', 'shared');
create type public.location_precision as enum ('exact', 'neighborhood', 'city', 'hidden');
create type public.narrative_source as enum ('user', 'on_device', 'chatgpt');

-- Entries keep the app's ids. The location columns hold only what may be
-- shared: the server reduces them to location_precision before writing.
create table public.entries (
  id uuid primary key,
  journal_name text not null default 'Main',
  occurred_at timestamptz not null,
  -- The calendar day as the writer saw it, independent of the reader's timezone.
  day date not null,
  title text not null default '',
  notes text not null default '',
  narrative text not null default '',
  narrative_source public.narrative_source not null default 'user',
  place_name text,
  latitude double precision,
  longitude double precision,
  location_precision public.location_precision not null default 'city',
  translation_language text not null default '',
  translated_title text not null default '',
  translated_notes text not null default '',
  translated_narrative text not null default '',
  visibility public.entry_visibility not null default 'private',
  -- Bumped on every text change from the owner; a narrative proposal records
  -- the revision it was written against.
  revision integer not null default 1 check (revision >= 1),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index entries_day_idx on public.entries (day);

create trigger entries_set_updated_at
  before update on public.entries
  for each row execute function public.set_updated_at();

-- ON DELETE RESTRICT on the tag: deleting a tag that entries still use would
-- leave them untagged, and untagged shared entries are visible to every
-- invite. The app refuses too; this makes the server refuse on its own.
create table public.entry_tags (
  entry_id uuid not null references public.entries (id) on delete cascade,
  tag_id uuid not null references public.tags (id) on delete restrict,
  primary key (entry_id, tag_id)
);

create index entry_tags_tag_idx on public.entry_tags (tag_id);

create type public.media_kind as enum ('photo', 'video');

create table public.entry_media (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries (id) on delete cascade,
  -- The app's Photos local identifier; unique per entry so uploads can be retried.
  asset_key text not null,
  kind public.media_kind not null,
  storage_path text not null,
  width integer,
  height integer,
  taken_at timestamptz,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  unique (entry_id, asset_key)
);

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  -- SHA-256 of the invite token. The token itself is shown once, never stored.
  token_hash text not null unique,
  created_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,
  last_seen_at timestamptz
);

-- Removing a tag from an invite only narrows what it sees, so a deleted tag
-- may cascade here.
create table public.invite_tags (
  invite_id uuid not null references public.invites (id) on delete cascade,
  tag_id uuid not null references public.tags (id) on delete cascade,
  primary key (invite_id, tag_id)
);

create type public.proposal_status as enum ('pending', 'accepted', 'rejected', 'superseded');

-- Story text proposed by an agent. Only the owner accepts or rejects; an
-- accepted proposal becomes the entry's narrative through the app.
create table public.narrative_proposals (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries (id) on delete cascade,
  base_revision integer not null,
  text text not null check (length(trim(text)) > 0),
  agent_name text not null,
  status public.proposal_status not null default 'pending',
  created_at timestamptz not null default timezone('utc', now()),
  decided_at timestamptz
);

create index narrative_proposals_entry_idx on public.narrative_proposals (entry_id, status);

create table public.api_idempotency_keys (
  key_name text not null,
  idempotency_key text not null,
  operation text not null,
  request_hash text not null,
  status_code integer not null,
  response jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (key_name, idempotency_key)
);

-- The all-tags rule in SQL, matching isVisibleToInvite in
-- web/src/lib/domain/visibility.ts: a shared entry is visible when none of its
-- tags is missing from the invite. Revoked invites see nothing.
create or replace function public.entries_visible_to_invite(p_invite_id uuid)
returns setof public.entries
language sql
stable
as $$
  select e.*
  from public.entries e
  where e.visibility = 'shared'
    and exists (
      select 1 from public.invites i
      where i.id = p_invite_id and i.revoked_at is null
    )
    and not exists (
      select 1
      from public.entry_tags et
      where et.entry_id = e.id
        and not exists (
          select 1
          from public.invite_tags it
          where it.invite_id = p_invite_id
            and it.tag_id = et.tag_id
        )
    );
$$;

alter table public.tags enable row level security;
alter table public.entries enable row level security;
alter table public.entry_tags enable row level security;
alter table public.entry_media enable row level security;
alter table public.invites enable row level security;
alter table public.invite_tags enable row level security;
alter table public.narrative_proposals enable row level security;
alter table public.api_idempotency_keys enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke execute on function public.entries_visible_to_invite(uuid) from public, anon, authenticated;

-- Private bucket for entry photos and videos; the server hands out signed URLs.
insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;
