# Journey website

The website and API of [Journey](../README.md). Friends and family you invite
read the entries you publish from the iPhone app; a custom ChatGPT GPT reads
the journal through an agent API and proposes story text for you to accept or
reject in the app.

Next.js 15 (App Router) and TypeScript, pnpm, Vitest, Supabase (Postgres and
Storage), deployed on Netlify. Commands below run from this `web/` folder.

## Status

In place: the Netlify build, database schema, owner publishing API, invite
reader at `/read`, signed private media, owner dashboard at `/owner`, durable
media-cleanup queue, and local-database integration CI. The GPT's agent API
comes next.

## Sharing rules

An invite sees a shared entry only if the invite includes **all** of the
entry's tags; untagged shared entries are visible to every invite, and private
entries to none. The rule lives in two places that must agree:
[`src/lib/domain/visibility.ts`](src/lib/domain/visibility.ts) and
`public.entries_visible_to_invite` in the
[schema](supabase/migrations/20260913120000_initial_schema.sql).

Locations are reduced to the entry's sharing precision on the server before
they're stored ([`location.ts`](src/lib/domain/location.ts)). City precision —
the default — keeps the city and coordinates to about 11 km, and drops the
specific place name.

## Owner API

The API the iPhone app publishes through, under `/api/v1/owner`, with the
owner key. The contract is served at
[`/api/v1/owner/openapi.json`](src/lib/api/owner-openapi.ts), and a test keeps
it and the route handlers in step.

| Endpoint | Does |
| -------- | ---- |
| `GET /tags`, `PUT /tags/{id}`, `DELETE /tags/{id}` | Tags keep the app's ids. A tag still on an entry can't be deleted (`409 TAG_IN_USE`). |
| `GET`, `PUT`, `DELETE /entries/{id}` | Publish, update or unpublish an entry. The location is reduced to its precision before storing; the revision moves only when the title, notes or story change; `media_keys` sets the entry's photos and the reply lists the ones still to upload. |
| `PUT`, `DELETE /entries/{id}/media/{key}` | A JPEG up to 5 MB with its metadata stripped — the server refuses EXIF, XMP and IPTC, which can carry the location. |
| `GET /invites`, `POST /invites`, `DELETE /invites/{id}` | Create an invite limited to tags (its token and link are returned once; only a hash is stored), list them, revoke one. |
| `GET /proposals`, `POST /proposals/{id}/decision` | The GPT's story proposals, marked `stale` when written against older text; accept or reject. Accepting doesn't touch the entry — the app applies the text and republishes. |

Saving an entry and creating an invite each happen in one database
transaction (`save_entry`, `create_invite`), so an entry is never briefly left
with fewer tags — and so visible to more invites — than before or after.

## Running it locally

Needs Node 22 (`nvm use 22`) and pnpm, which comes with Node via corepack.

```sh
corepack enable
pnpm install
cp .env.example .env.local   # then fill in the values
pnpm dev                     # http://localhost:3000
```

| Command | What it does |
| ------- | ------------ |
| `pnpm dev` | Local server with hot reload |
| `pnpm typecheck` | TypeScript, no emit |
| `pnpm test` | Vitest |
| `pnpm build` | Production build, the same one Netlify runs |
| `pnpm test:sql` | Every `supabase/tests/*.sql` file against `LOCAL_DB_URL` (localhost only) |
| `pnpm test:e2e:owner` | Owner API, login, session, dashboard, detail and media against localhost |
| `pnpm test:e2e:reader` | Invite, policy-matrix, reader, media and revocation HTTP checks against localhost |
| `pnpm cleanup:media` | Preview queued Storage cleanup; add `-- --apply` after verifying the destination |

### Against a local database

Docker, then:

```sh
pnpm dlx supabase start        # local Postgres, API and storage
pnpm dlx supabase db reset     # apply every migration from scratch
LOCAL_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  pnpm test:sql
```

[`scripts/owner-e2e.mjs`](scripts/owner-e2e.mjs) drives every owner endpoint
against a local server and the local stack, and refuses to run against
anything else. [`scripts/reader-e2e.mjs`](scripts/reader-e2e.mjs) covers the
browser reader authorization boundary. Their headers and
[`../docs/operations.md`](../docs/operations.md) show the required environment
and the complete local-CI sequence.

## API keys

`JOURNEY_API_KEYS` is a JSON array of keys, each with a role:

```json
[
  { "name": "iphone", "secret": "long-random-token", "role": "owner" },
  { "name": "chatgpt", "secret": "another-long-random-token", "role": "agent" }
]
```

| Role | Who | Can |
| ---- | --- | --- |
| `owner` | the iPhone app | publish and unpublish entries, manage invites, accept or reject proposals |
| `agent` | the ChatGPT GPT | read entries, propose story text |
| `agent-read` | a read-only agent | read entries |

Invitations are managed from the app: each one is created with the tags it may
read, and those tags can be changed afterwards, its link replaced (which kills
the old one immediately), or the invitation revoked. The list shows how many
entries each one actually reads.

The agent can never publish, delete, or decide on its own proposals. Secrets
must be at least 24 characters; `openssl rand -base64 32` makes a good one.
Requests send `Authorization: Bearer <secret>`.

## Database (Supabase)

1. Create a project at [supabase.com](https://supabase.com).
2. Apply the migrations in [`supabase/migrations/`](supabase/migrations), in
   order: paste each into the SQL editor, or with the CLI:

   ```sh
   pnpm dlx supabase link --project-ref <your-project-ref>
   pnpm dlx supabase db push
   ```

3. From **Project Settings → API**, copy the project URL and the
   **service_role** key for the Netlify environment variables below.

Only the server talks to the database, with the service-role key. Row-level
security is on with no policies, so the public keys can read nothing.

## Video storage (Cloudflare R2)

Photos live in Supabase Storage. Videos live in [Cloudflare
R2](https://developers.cloudflare.com/r2/), because they are far larger and R2
charges nothing for egress: its free tier is 10 GB against Supabase's 1 GB, and
serving a clip costs no bandwidth. Which store holds an object is recorded in
`entry_media.storage_path`, where an `r2:` prefix means R2.

1. In the Cloudflare dashboard, **R2 → Create bucket**. Keep it private: the
   site hands out short-lived signed URLs and never makes the bucket public.
2. **R2 → Manage API tokens → Create API token**, with *Object Read & Write*
   scoped to that bucket. Copy the access key id and secret once.
3. Note the account id from the R2 overview page.
4. Set `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and
   `R2_BUCKET` in Netlify, scoped to **Builds and Functions**.

Leave them unset for local development and videos fall back to Supabase
Storage, which is what the e2e scripts use; never leave them unset in
production.

A video is uploaded straight from the phone to the store with a presigned URL,
because a Netlify function's request body caps at 6 MB. The server therefore
sees the bytes only afterwards, at the commit step, where it refuses anything
carrying location metadata, not exported for streaming, or over 60 MB.

## Deploying to Netlify

Build settings live in [`../netlify.toml`](../netlify.toml): it builds from
`web/` with Node 22, and skips deploys for commits that only touch the iOS
app.

One-time setup in the Netlify UI:

1. **Add new project → Import an existing project → GitHub**, and pick
   `cpascoli/journey`.
2. Leave **Base directory** empty — `netlify.toml` sets it — and keep the
   production branch as `main`.
3. Under **Project configuration → Environment variables**, add these with the
   scope **Builds and Functions**, never as `NEXT_PUBLIC_*`:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `JOURNEY_API_KEYS`
   - `JOURNEY_SESSION_SECRET` (an independent random value of at least 32 characters)
   - `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`
4. Deploy. After that, every push to `main` that touches `web/` deploys to
   production, so a push is a release.

GitHub Actions ([`web.yml`](../.github/workflows/web.yml)) type-checks, tests
and builds the site, then starts a pinned local Supabase stack, resets it,
runs every SQL test, and exercises the owner and reader HTTP surfaces.
Operational backup, recovery, rotation, rollback and cleanup procedures are in
[`docs/operations.md`](../docs/operations.md).
