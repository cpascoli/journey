# Journey operations

This runbook covers the Supabase/Netlify website and the iPhone publishing
destination. Commands run from `web/` unless stated otherwise. Never use the
local integration scripts against production.

## Before an incident

- Keep Supabase automated backups enabled and record their retention and
  point-in-time recovery window.
- Before every schema release, take or verify a backup and run the migration,
  SQL tests, and HTTP tests against a local reset or disposable project.
- Store `SUPABASE_SERVICE_ROLE_KEY`, `JOURNEY_API_KEYS`, and
  `JOURNEY_SESSION_SECRET` in a secrets manager. Keep an offline recovery copy
  of the active iPhone owner key; it is otherwise device-only.
- Quarterly, restore a backup into a separate project and verify entry, tag,
  invite, proposal, media-row, cleanup-queue, and private Storage counts.
  Open representative owner and invite pages before destroying the drill.

## Backup and restore

Supabase's managed backup/PITR is the primary whole-project recovery path.
Use its dashboard recovery workflow for an in-place incident. For a portable
logical database backup, use the direct database connection and avoid putting
its password in shell history:

```sh
read -s PGPASSWORD; export PGPASSWORD
pg_dump --format=custom --no-owner --no-acl \
  --host <db-host> --port 5432 --username postgres --dbname postgres \
  --file journey-$(date +%Y%m%dT%H%M%S).dump
unset PGPASSWORD
```

Restore only into an empty, isolated destination first:

```sh
read -s PGPASSWORD; export PGPASSWORD
pg_restore --clean --if-exists --no-owner --no-acl \
  --host <recovery-host> --port 5432 --username postgres --dbname postgres \
  journey-YYYYMMDDTHHMMSS.dump
unset PGPASSWORD
```

Database dumps do not contain Storage objects. Preserve Supabase Storage with
the provider's project backup/recovery facilities or a separately encrypted
object export. After restore, compare `entry_media.storage_path` with objects
in the private `media` bucket; do not make the bucket public to recover files.
Switch Netlify only after testing the isolated restore.

## Migrations: forward fixes only

Applied migration files are immutable. If a release migration is wrong:

1. Stop publishing by disabling the affected Netlify deploy or owner keys if
   writes would worsen damage.
2. Capture the failing migration, database error, and current migration list.
3. Reproduce from `supabase db reset` locally.
4. Add a new timestamped migration that moves the current production schema
   forward. Do not edit an already-applied migration or manually mark it
   reverted.
5. Run `pnpm test:sql`, unit tests, build, and both HTTP end-to-end scripts
   locally or in CI.
6. Apply the forward fix, verify row/object counts, and run a read-only smoke
   test. Use backup/PITR recovery only when a forward fix cannot preserve data.

## Key and session-secret rotation

### Owner or agent API key

For an agent key, add the replacement to `JOURNEY_API_KEYS`, deploy, verify it,
move the client, then remove the old key and deploy again. Confirm the agent
role still lacks publish, invite-management, and proposal-decision scopes.

For a planned iPhone owner-key rotation:

1. With the old key active, unpublish every bound entry and wait for the outbox
   to empty.
2. Add the new owner key, deploy, verify it, and replace the key in Settings.
3. Remove the old key and deploy again. Owner browser sessions made with it
   become invalid because sessions include the key fingerprint.
4. Republish the intended entries.

The app intentionally will not replace an owner key while publications remain
bound to its fingerprint. For suspected owner-key disclosure, remove the
exposed server key immediately and contain the site. Use a new owner key to
remove exposed server copies. Preserve the phone and its destination records;
the current app has no self-service way to clear a binding whose old key was
revoked before unpublish, so recovery requires a supported data repair rather
than editing or deleting the local store.

### `JOURNEY_SESSION_SECRET`

Generate an independent value of at least 32 random characters, replace the
Netlify variable, and deploy. Rotation deliberately signs every owner browser
session out; it does not rotate API keys or invite tokens.

### Supabase service-role key

Rotate it in Supabase, update the scoped Netlify variable, deploy, and verify
owner and reader requests. Treat the old key as fully privileged until it is
revoked.

## Destination migration and recovery

The app binds online entries and queued work to a normalized website URL plus
owner-key fingerprint. It blocks changing either while bindings remain.

- Rename (same server, new address): in Settings → Website, type the new
  address and tap **Move to This Address**. The app reads a published entry
  back from the new address and requires its content hash to match before
  rebinding, so it cannot be pointed at a different journal. Nothing on the
  website changes. Do not unpublish first: that deletes entries, and their
  media and readers' comments cascade with them.
  Afterwards, replace each invitation's link (Settings → Sharing →
  Invitations → the invitation → Replace Link) so readers are on the new host;
  links already shared keep working through the redirect in `netlify.toml`.
- Move to a different server or key: keep the old destination/key available,
  unpublish all entries, wait until the outbox is empty, change the
  website/key, then republish. This loses comments, which cascade with their
  entries.
- Lost iPhone key: restore the exact old owner key from the recovery copy so
  queued updates/removals can finish. A different key cannot impersonate that
  binding.
- Lost old server but intact backup: restore its database, private media, URL,
  and old owner-key configuration long enough to finish/unpublish.
- Unrecoverable destination: do not clear local bindings by editing app data.
  Record the affected entry IDs and old URL, contain the old site at DNS/
  Netlify, and recover from Supabase/Netlify support or backup before moving.

## Invite incident

For a leaked or misdirected invite, revoke it in `/owner` immediately. The next
reader page and media authorization request is denied. A Storage URL already
signed remains usable only for its short TTL (currently 90 seconds), so wait
that window before declaring containment complete. Create a replacement invite
instead of trying to recover the one-time token. If access scope was too broad,
also correct entry tags/visibility and verify with the replacement invite.

## Netlify rollback

In Netlify, open **Deploys**, select the last known-good production deploy, and
publish/restore it. A rollback changes code only: it does not undo a Supabase
migration. If the new code wrote incompatible data, keep the site contained
until a forward migration and compatible deploy are ready. After rollback,
check `/`, `/owner/login`, an owner entry, one valid invite, one revoked invite,
and one media redirect without copying tokens into tickets or logs.

## Media cleanup and reconciliation

Media is private. Entry/media deletion removes the database reference first;
a failed Storage deletion is recorded in `storage_cleanup_queue` for retry.
Monitor queue age and attempts with a service-role or SQL-console query:

```sql
select storage_path, attempts, created_at, last_attempt_at, last_error
from public.storage_cleanup_queue
order by created_at;
```

Preview and then run reconciliation in bounded batches until the queue is
empty:

```sh
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... pnpm cleanup:media
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... pnpm cleanup:media -- --apply
```

The command is dry-run by default and processes at most 100 queued paths per
applied run. Verify `SUPABASE_URL` before `--apply`. Queued paths beginning
`r2:` are video objects in Cloudflare R2, so pass `R2_ACCOUNT_ID`,
`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and `R2_BUCKET` too; without them
the preview says how many it cannot touch and an applied run reports them as
failures rather than clearing them. Never delete an object unless no
`entry_media.storage_path` references it. Separately investigate referenced
objects missing from Storage and unreferenced objects older than active upload
windows; restore or quarantine before deletion when uncertain.

## Logs and privacy

Use Netlify function logs and Supabase API/Postgres/Storage logs for status
codes, route names, timestamps, and provider request IDs. Never log or paste:

- Authorization headers, API/service-role keys, session or invite cookies;
- `/i/<token>` URLs or signed Storage query strings;
- precise local coordinates, entry text, or uploaded media; or
- raw database errors in HTTP responses.

Redact before sharing an incident artifact, limit retention/access, and rotate
any secret that entered logs.

## Local CI parity

Requires Node 22, pnpm, Docker, `psql`, Xcode 26, XcodeGen, and an iOS 26
simulator:

```sh
cd web
pnpm install --frozen-lockfile
pnpm typecheck && pnpm test && pnpm build
pnpm dlx supabase@2.117.0 start
pnpm dlx supabase@2.117.0 db reset
eval "$(pnpm dlx supabase@2.117.0 status -o env)"
LOCAL_DB_URL="$DB_URL" pnpm test:sql

export SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
export OWNER_TOKEN=journey-local-owner-token-000000000000
export AGENT_TOKEN=journey-local-agent-token-000000000000
export JOURNEY_SESSION_SECRET=journey-local-session-secret-000000000000000000
export JOURNEY_API_KEYS='[{"name":"local-owner","secret":"journey-local-owner-token-000000000000","role":"owner"},{"name":"local-agent","secret":"journey-local-agent-token-000000000000","role":"agent"}]'
pnpm start
# In another shell:
pnpm test:e2e:owner && pnpm test:e2e:reader
pnpm dlx supabase@2.117.0 stop --no-backup

cd ../ios
xcodegen generate
xcodebuild test -project Journey.xcodeproj -scheme Journey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:JourneyTests CODE_SIGNING_ALLOWED=NO
```

The e2e scripts enforce localhost. Never weaken that check or point SQL reset/
tests at a hosted database.
