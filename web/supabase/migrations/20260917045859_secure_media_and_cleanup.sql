-- Durable cleanup for Storage objects whose database references have already
-- been removed. Only the service-role server may inspect or mutate this queue.
create table public.storage_cleanup_queue (
  storage_path text primary key check (length(storage_path) > 0),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at timestamptz not null default timezone('utc', now()),
  last_attempt_at timestamptz
);

alter table public.storage_cleanup_queue enable row level security;
revoke all on public.storage_cleanup_queue from public, anon, authenticated;
grant select, insert, update, delete on public.storage_cleanup_queue to service_role;

-- Exact media authorization for an invite. Keeping the all-tags check in this
-- query prevents a media URL from outliving an entry visibility/tag change or
-- invite revocation.
create or replace function public.media_visible_to_invite(
  p_token_hash text,
  p_entry_id uuid,
  p_asset_key text
)
returns table (storage_path text)
language sql
stable
set search_path = ''
as $$
  select em.storage_path
  from public.invites i
  join public.entries e on e.id = p_entry_id
  join public.entry_media em
    on em.entry_id = e.id and em.asset_key = p_asset_key
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

revoke execute on function public.media_visible_to_invite(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.media_visible_to_invite(text, uuid, text)
  to service_role;
