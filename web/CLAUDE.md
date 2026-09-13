# Journey — website

Next.js 15 (App Router) + TypeScript website and API, deployed on Netlify. See
README.md in this folder for setup and deployment, and `../CLAUDE.md` for the
sharing rules and planned design shared with the iPhone app.

Paths and commands below are relative to `web/`.

## Commands

```sh
pnpm install
pnpm typecheck
pnpm test        # Vitest, src/**/*.test.ts
pnpm build       # what Netlify runs
```

Node 22 lives in nvm (`~/.nvm`); a non-interactive shell may still find the
system Node 18 first, so prefix commands with
`export PATH="$HOME/.nvm/versions/node/v22.23.2/bin:$PATH"` if `node -v` says 18.

## Layout

```
src/app/            pages and API route handlers (app router)
src/lib/domain/     pure rules, unit-tested: visibility, location precision
src/lib/api/        API plumbing: keys and scopes, errors, validation, HTTP, OpenAPI
src/lib/owner/      owner API rules: entry payloads, photo checks, invite tokens
src/lib/supabase/   the service-role client and database error mapping
supabase/migrations SQL schema, applied to the hosted project with `supabase db push`
supabase/tests      SQL tests, run against the local stack (see README)
scripts/            owner-e2e.mjs — end-to-end run against localhost only
```

Keep pure logic in `src/lib/domain`, where Vitest reaches it.

## Rules

- **Pushing to `main` deploys to production.** Netlify builds from `main`, so
  ask before every push; approval of the work is not approval to push it.
- The service-role key and `JOURNEY_API_KEYS` are server-only. Never read them
  in client components, never name them `NEXT_PUBLIC_*`, never log them.
- The all-tags visibility rule exists twice — `isVisibleToInvite` and
  `public.entries_visible_to_invite` — and they must stay equivalent. Change
  both together, with tests.
- Reduce locations with `shareLocation` before storing; never store the precise
  value "for later".
- The `agent` role must never gain `entries:write`, `invites:manage` or
  `proposals:decide`. `keys.test.ts` asserts this.
- Migrations are additive and never edited once pushed: add a new file.
  Functions created in `public` are executable by the public roles by
  default: revoke from `public, anon, authenticated` and grant `service_role`.
- Any write that changes an entry's tags or visibility goes through one SQL
  function (`save_entry`), never separate calls: a half-applied tag change
  leaves an entry visible to more invites than intended.
- Photos must arrive metadata-free; the server refuses EXIF, XMP and IPTC
  (`findPhotoMetadata`). Don't relax that to "strip on the server".
- Error responses never echo database or exception messages: `dbFailure` logs
  and returns a generic error.
- Never pass a secret as a command-line argument in a script whose errors are
  printed: Node's child_process errors include the full command.
- `scripts/owner-e2e.mjs`, `supabase db reset` and the SQL tests are for the
  local stack only. Never point them at the hosted project.
- GPT Actions import the agent OpenAPI document. Keep it 3.1.0 with no `oneOf`,
  `anyOf`, `allOf` or `$ref`, every object schema with `properties`, and every
  summary, description and parameter description at most 300 characters —
  powerfund's `surface.test.ts` is the model for the test that enforces it.
