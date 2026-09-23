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
pnpm test:sql    # all supabase/tests/*.sql; LOCAL_DB_URL must be localhost
pnpm test:e2e:owner
pnpm test:e2e:reader
```

Node 22 lives in nvm (`~/.nvm`); a non-interactive shell may find an older Node
first, so if `node -v` isn't 22, prefix commands with
`export PATH="$HOME/.nvm/versions/node/$(ls ~/.nvm/versions/node | grep '^v22' | sort -V | tail -1)/bin:$PATH"`.
pnpm is pinned by `packageManager`, so run it as `corepack pnpm …` when the
system pnpm is a different version.

## Layout

```
src/app/            pages and API route handlers (app router)
src/lib/domain/     pure rules, unit-tested: visibility, location precision
src/lib/api/        API plumbing: keys and scopes, errors, validation, HTTP, OpenAPI
src/lib/owner/      owner API rules: entry payloads, photo checks, invite tokens
src/lib/supabase/   the service-role client and database error mapping
supabase/migrations SQL schema, applied to the hosted project with `supabase db push`
supabase/tests      SQL tests, run against the local stack (see README)
scripts/            portable SQL runner, localhost HTTP e2e, cleanup operator
```

Keep pure logic in `src/lib/domain`, where Vitest reaches it.

The owner dashboard lists only the days that have entries and fetches no
media; entries and their photos load for the one day opened
(`/owner/day/[day]`). Read one entry with `ownerEntry`, which queries by id —
never by loading everything published and filtering.

## Rules

- **Pushing to `main` deploys to production.** Netlify builds from `main`, so
  ask before every push; approval of the work is not approval to push it.
- The service-role key and `JOURNEY_API_KEYS` are server-only. Never read them
  in client components, never name them `NEXT_PUBLIC_*`, never log them.
- The all-tags visibility rule exists twice — `isVisibleToInvite` and
  `public.entries_visible_to_invite` — and they must stay equivalent. Change
  both together, with tests.
- Build every link the site hands out with `publicOrigin`, never
  `new URL(request.url).origin`: behind Netlify's runtime that carried the
  branch-deploy hostname (`main--<site>.netlify.app`) and invite links were
  minted on it. `JOURNEY_PUBLIC_ORIGIN` pins the answer.
- Reduce locations with `shareLocation` before storing; never store the precise
  value "for later".
- The `agent` role must never gain `entries:write`, `invites:manage` or
  `proposals:decide`. `keys.test.ts` asserts this.
- A media-writing SQL function is versioned rather than edited when its
  arguments change (`commit_media_upload_v2`): the locking and the
  cleanup-queue claim in it are what stop a cleanup worker racing an upload
  into a dangling row, so copy them verbatim into any successor.
- Migrations are additive and never edited once pushed: add a new file.
  Functions created in `public` are executable by the public roles by
  default: revoke from `public, anon, authenticated` and grant `service_role`.
- The dashboard may correct an entry's text through `save_entry_text`, which
  touches only the text columns. Tags and visibility decide who may read an
  entry, so a text edit must not be able to reach them; keep that function
  narrow. It bumps `revision` (staling proposals) and clears
  `client_content_hash`, because the website no longer holds what the app
  sent. The app stays the source of truth and overwrites on its next publish.
- Any write that changes an entry's tags or visibility goes through one SQL
  function (`save_entry`), never separate calls: a half-applied tag change
  leaves an entry visible to more invites than intended. An invite's tags obey
  the same rule through `set_invite_tags`, and the API takes the complete set,
  never add/remove.
- Replacing an invite's link (`rotate_invite_token`) overwrites the hash in one
  statement, so the old link dies as the new one is born, and it refuses a
  revoked invite — rotating must never quietly restore access.
- A listing shows at most four thumbnails per entry and a "+N" tile leading
  to it; the entry itself shows them all. An entry with thirty photos was
  putting thirty thumbnails on a page meant to be skimmed.
- The grid asks for a photo's small copy (`/media/…?size=thumb`) and the
  viewer for the original, falling back to the original when no thumbnail
  exists so media published before them still loads. A thumbnail carries the
  same location as a full image, so it is held to the same metadata rule.
  Its cleanup is a trigger on `entry_media`, which keeps every existing
  deletion path correct without versioning four functions.
- Photos must arrive metadata-free; the server refuses EXIF, XMP and IPTC
  (`findPhotoMetadata`). Don't relax that to "strip on the server".
- Videos are the same rule with a different file format: `findVideoMetadata`
  refuses QuickTime and 3GPP location atoms and Apple's `mdta` location key.
  Because a video is uploaded straight to the object store (a Netlify body
  caps at 6 MB), the commit step is the only place the server sees the bytes —
  and it reads only the head, so it also refuses any file whose `moov` is not
  at the front. Never accept a video the server has not inspected.
- Photos live in Supabase Storage, videos in Cloudflare R2. The store is
  encoded in `entry_media.storage_path` (`r2:` prefix) and nowhere else: a
  separate column could disagree with `storage_cleanup_queue`, which is keyed
  on the path alone, and send a delete to the wrong store.
- SigV4 signing lives once, in `src/lib/media/sigv4.mjs`, because the operator
  cleanup script runs under bare node and must share it. Don't copy it.
- Comments are the only thing a reader may write. Authorization is not in the
  route: `commentable_invite` re-applies the all-tags rule, so a reader can
  only see or add comments on an entry their invitation can already read, and
  losing access hides the conversation without deleting it.
- A comment thread is private to one invitation, the owner's replies included.
  Never widen `comment_thread_for_invite` to join threads: an invitee must not
  learn who else was invited.
- An invite link is a bearer token, so `post_reader_comment` enforces an
  hourly limit per invitation in SQL. Keep the limit there rather than in a
  route, where it would not survive a second entry point.
- The `agent` roles must never gain `journey:comments:manage`; comments are
  private correspondence. `keys.test.ts` asserts it.
- Error responses never echo database or exception messages: `dbFailure` logs
  and returns a generic error.
- Never pass a secret as a command-line argument in a script whose errors are
  printed: Node's child_process errors include the full command.
- The HTTP e2e scripts, `supabase db reset`, and SQL tests are for the local
  stack only. Never point them at the hosted project. `cleanup:media` is an
  operator command: it previews by default; verify `SUPABASE_URL` before
  passing `--apply`. `backfill:thumbnails` is the same kind of command, and
  uploads through the owner API rather than writing to storage, so no rule
  about what may be published lives in a script.
- GPT Actions import the agent OpenAPI document. Keep it 3.1.0 with no `oneOf`,
  `anyOf`, `allOf` or `$ref`, every object schema with `properties`, and every
  summary, description and parameter description at most 300 characters —
  powerfund's `surface.test.ts` is the model for the test that enforces it.
