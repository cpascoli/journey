# Journey

Monorepo for a personal travel journal.

- `ios/` — the iPhone app. `ios/CLAUDE.md` has its build commands, code rules
  and gotchas; commands there run from `ios/`.
- `web/` — the website and API. Not started yet.
- `api/openapi.yaml` — the API contract. Not started yet. Once it exists it is
  the source of truth for the website's routes, the GPT's actions and the
  app's upload code: change the contract first, then both sides, in the same
  commit.

## Sharing rules (app and website)

Tags double as sharing rules:

- An invite may see an entry only if the invite includes **all** of the
  entry's tags. Untagged entries are visible to every invite.
- Nothing is shared unless it's published: entries also have a visibility
  (local only / private sync / public), so untagged ≠ published.
- Never let an edit widen access implicitly. A tag that's in use can't be
  deleted (it would leave entries untagged, i.e. visible to everyone), and
  tags are referenced by `id`, so renames are safe.
- The website's server enforces access. Never rely on a client to filter.

## Planned direction

Decisions already made, so new work fits them:

- **Map view** in the app (clustered pins), alongside the calendar.
- **Narration history:** a revision history per entry, so ChatGPT proposals
  can be accepted, rejected or reverted to an earlier version.
- **Publishing:** the website exposes an agent-friendly API; a custom GPT uses
  it to read entries and submit narrative *proposals* tied to the revision
  they're based on. The app accepts or rejects them; only accepted text is
  ever public. The GPT's token must not be able to delete or publish.
- Published locations default to city level.
- A ChatGPT subscription gives no API access, so nothing in the project calls
  OpenAI.

## Working in this repo

- One topic per commit. Keep app and website changes in separate commits
  unless they change the API contract together.
