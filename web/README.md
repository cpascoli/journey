# Journey website

The website and API of [Journey](../README.md). Friends and family you invite
read the entries you publish from the iPhone app; a custom ChatGPT GPT reads
the journal through an agent API and proposes story text for you to accept or
reject in the app.

Next.js 15 (App Router) and TypeScript, pnpm, Vitest, Supabase (Postgres and
Storage), deployed on Netlify. Commands below run from this `web/` folder.

## Status

The foundation is in place: the Netlify build, the landing page, the database
schema, and the rules everything else builds on — who can see an entry, how
precisely a location is shared, and which API key may do what. The owner API
(publishing from the app), invites and reading pages, and the GPT's agent API
come next.

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

The agent can never publish, delete, or decide on its own proposals. Secrets
must be at least 24 characters; `openssl rand -base64 32` makes a good one.
Requests send `Authorization: Bearer <secret>`.

## Database (Supabase)

1. Create a project at [supabase.com](https://supabase.com).
2. Apply the schema: paste
   [`supabase/migrations/20260913120000_initial_schema.sql`](supabase/migrations/20260913120000_initial_schema.sql)
   into the SQL editor, or with the CLI:

   ```sh
   pnpm dlx supabase link --project-ref <your-project-ref>
   pnpm dlx supabase db push
   ```

3. From **Project Settings → API**, copy the project URL and the
   **service_role** key for the Netlify environment variables below.

Only the server talks to the database, with the service-role key. Row-level
security is on with no policies, so the public keys can read nothing.

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
4. Deploy. After that, every push to `main` that touches `web/` deploys to
   production, so a push is a release.

GitHub Actions ([`web.yml`](../.github/workflows/web.yml)) type-checks, tests
and builds the site on every push that touches it.
