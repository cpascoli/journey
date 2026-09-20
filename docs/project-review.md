# Journey project review

Reviewed 17 September 2026 and updated for the current step-6 working tree.

## Executive assessment

Journey is a strong prototype with a coherent product idea and a better privacy
model than many production projects. The iPhone app already has a useful local
experience, and the website has a carefully designed owner API and database
foundation. The code is generally small, direct, documented, and organized
around domain rules rather than framework plumbing.

The iPhone app now implements durable, destination-bound owner publishing with
stable local days, versioned SwiftData migrations, cached city locality,
metadata-free JPEG export, missing-asset preservation, retry/reconciliation,
and update/unpublish recovery.

The website now implements invite-token exchange, an HTTP-only reader cookie,
all-tags entry authorization, reader list/detail pages, short-lived signed
private-media redirects, immediate revocation checks, and an authenticated
owner dashboard. The remaining major product boundary is the agent
read/proposal API and iOS proposal/revision-history UI.

I found no current P0 security flaw. There are, however, several issues that
should be treated as release blockers before inviting readers or relying on
the app as the only copy of irreplaceable journal data:

1. The iOS store still has no user export/import or enabled backup/sync. A
   detailed personal journal should not have one device as its only copy.
2. Proposal staleness only follows changes to title, notes, and narrative.
   Changes to place, date, location, translation, tags, or media can leave a
   proposal marked current even though its source facts changed.

The publisher/reader security slice now has SQL and localhost HTTP integration
coverage in CI. The next product milestone can focus on narration history and
the restricted agent proposal flow, while export/backup remains a prerequisite
for treating the phone as the durable home of irreplaceable writing.

## What is working well

### Product and documentation

- The three READMEs explain the product, current status, setup, privacy model,
  and planned direction clearly. They are more honest than typical prototype
  documentation about what exists and what is still planned.
- The demo mode is a good product-development tool. It protects real data,
  creates a reproducible story, and makes UI progress visible
  (`ios/Journey/Demo/DemoData.swift`, `ios/Tools/record-demo.sh`).
- The concepts fit together: visits create context, photos fill historical
  gaps, entries preserve the user's notes separately from generated narration,
  and tags serve both organization and sharing.

### iPhone app

- The app minimizes battery use by using Core Location visits instead of
  continuous tracking (`ios/Journey/Services/LocationService.swift`).
- Media remains in Photos and entries retain identifiers rather than copying
  a second private media library (`ios/Journey/Models/Entry.swift:14-15`).
- AI-generated narrative is separated from the user's notes, and its source is
  recorded (`ios/Journey/Models/Entry.swift:16-21`,
  `ios/Journey/Views/EntryEditorView.swift:407-414`).
- The photo-place clustering radius intentionally matches the timeline
  matching radius, preventing a photo-created visit from continually
  recreating itself (`ios/Journey/Services/PhotoPlaces.swift:6-10`).
- In-use tags cannot be deleted, which preserves the conservative all-tags
  sharing rule (`ios/Journey/Views/SettingsView.swift:161-167`).
- The calendar, journal page, media viewer, dictation, translation, demo mode,
  and appearance settings form a substantial local-first experience rather
  than a collection of disconnected experiments.
- The new owner client maps the deliberate contract differences explicitly,
  including `body` to `notes`, visibility raw values, nested translations, and
  `onDevice`/`chatGPT` to `on_device`/`chatgpt`
  (`ios/Journey/Services/JourneyAPI.swift`,
  `ios/Journey/Services/Publisher.swift:90-143`).
- The owner key is stored as `AfterFirstUnlockThisDeviceOnly` in the Keychain,
  while the website URL is restricted to HTTPS
  (`ios/Journey/Services/Keychain.swift:19-27`,
  `ios/Journey/Services/JourneyAPI.swift:21-26`).
- Photo export applies orientation, resizes to 2048 pixels, re-encodes as JPEG,
  strips the same location-bearing segments the server rejects, and uses a
  hashed media key rather than sending a Photos identifier
  (`ios/Journey/Services/PhotoExport.swift`).
- Publishing requires an explicit audience and location precision, warns that
  untagged shared entries reach every invite, explains skipped videos, and
  blocks deletion of entries and journals still known to be published
  (`ios/Journey/Views/PublishSheet.swift`,
  `ios/Journey/Views/DayView.swift:52-64`,
  `ios/Journey/Views/SettingsView.swift:212-223`).

### Website and API

- Access is denied by default. Only the server uses the service-role client,
  RLS is enabled, and public roles have no table policies
  (`web/supabase/migrations/20260913120000_initial_schema.sql:170-181`).
- The all-tags rule is explicit in TypeScript and SQL and has tests in both
  layers (`web/src/lib/domain/visibility.ts`,
  `web/supabase/tests/visibility.sql`).
- Entry and tag changes are made atomically by `save_entry`, preventing a
  temporary reduction in tags from widening access
  (`web/supabase/migrations/20260913130000_owner_api.sql:6-85`).
- Location precision is enforced before storage, not merely at read time
  (`web/src/lib/owner/entries.ts:53-65`,
  `web/src/lib/domain/location.ts:32-61`).
- Invite tokens have 192 bits of randomness, are returned once, and are stored
  only as SHA-256 hashes (`web/src/lib/owner/invites.ts`).
- Agent scopes are separated from owner capabilities. The agent role cannot
  publish, delete, manage invites, or decide proposals
  (`web/src/lib/api/scopes.ts:11-20`).
- JPEG uploads are bounded and reject EXIF, XMP, APP1, and IPTC metadata
  (`web/src/lib/owner/media.ts`,
  `web/src/app/api/v1/owner/entries/[id]/media/[key]/route.ts:27-50`).
- Error responses avoid exposing database messages
  (`web/src/lib/supabase/errors.ts`).

## Current implementation boundary

The current boundary is now:

- iOS-to-owner publishing, photo upload, update, unpublish, durable outbox,
  destination binding, and retry/reconciliation are implemented.
- Invite exchange, reader pages, owner dashboard, and signed media are
  implemented and covered by localhost HTTP integration tests.
- There is no agent API/OpenAPI document for reading entries and writing
  proposals.
- The iOS app manages invites, but proposal and revision-history UI remain.
- There is no map view.
- CloudKit compatibility is considered in model shape, but CloudKit sync is
  not enabled.

The root, iOS, and web READMEs now describe this implemented boundary and link
the operational runbook. Two model questions remain:

- The planned root model distinguishes local-only, private sync, and public,
  while the server currently models only `private` and `shared`; the eventual
  iOS sync state and server visibility should be named as separate concepts.
- Proposal status includes `superseded`, but no current code sets it. Define
  when a newer proposal or accepted decision supersedes older pending work.

## Findings and gaps

### Release blockers before sharing or durable personal use

#### 1. Calendar-day stability — resolved

Entries and visits now persist an additive `LocalDay` identity and timezone
context through a versioned SwiftData schema. Calendar grouping no longer
reinterprets old records solely through the device's current timezone, and
`LocalDayTests` covers timezone-boundary behavior.

#### 2. Data durability is below the value of the data

The app now has a `VersionedSchema`, migration plan, reconstructed historical
schema tests, and focused model/service tests. Remaining durability gaps are:

- no export/import;
- no enabled CloudKit sync or other backup;
- migration tests create their source stores from reconstructed schema
  declarations rather than fixtures produced by each previously shipped
  binary;
- a launch-time `fatalError` if the store cannot open
  (`ios/Journey/JourneyApp.swift`); and
- several swallowed persistence errors in location naming and photo-place
  creation.

User edits now save explicitly and surface persistence failures. Background
location naming and photo-derived place creation still need the same visible
health/error boundary.

Migration is now executable in `MigrationTests` and in iOS CI.

Recommendation:

- Add an explicit health/error boundary for background writes.
- Add store fixtures generated by every actually shipped app version, or an
  install-over test, so CI detects checksum drift between reconstructed and
  historical binaries.
- Provide an encrypted/exportable archive of journal text and metadata.
- Enable and test CloudKit only after conflict behavior and sharing boundaries
  are defined. CloudKit should be backup/sync, not an implicit publishing
  mechanism.
- Replace the fatal launch with a recovery screen that preserves the store and
  offers retry, diagnostics, and export. Never silently recreate an empty
  store.

#### 3. Publishing durability and destination binding — resolved

Publishing now persists a `PublishOperation` before network work, records
attempts/backoff and safe errors, reconciles ambiguous publish/unpublish
results through entry reads, preserves unpublish tombstones, and processes the
outbox on launch/activation. `PublishDestination` binds work to the normalized
server URL and key fingerprint; Settings blocks replacement while entries or
operations remain bound. Tag/journal changes enqueue affected publications,
and `PublishingOutboxTests` covers the state transitions.

The remaining lifecycle requirement is operational: retain an external
recovery copy of the device-only owner key. The procedure is documented in
`docs/operations.md`.

#### 4. Proposals can be incorrectly considered current

`save_entry` increments `revision` only when title, notes, or narrative
changes (`web/supabase/migrations/20260913130000_owner_api.sql:44-52`).
Proposal staleness compares only `base_revision` with that number
(`web/src/app/api/v1/owner/proposals/route.ts:35-44`).

A proposal may depend on the place, date, translation, tags, and media. Any of
those can change without making the proposal stale. Media ordering and
replacement happen outside `save_entry`, so media changes cannot affect the
revision at all.

Recommendation:

- Define an `agent_source_revision` or source fingerprint over every field the
  agent can read and use.
- Increment it atomically for location, time/day, text, relevant translation,
  and media-set changes.
- Keep a separate presentation revision if not every change should invalidate
  narration.
- Require an explicit confirmation to accept a stale proposal and preserve
  both the proposal and prior accepted narrative in revision history.

### High-priority correctness and security hardening

#### 5. Database/media divergence is recoverable

Supabase Storage and Postgres do not share a transaction:

- uploads use a fresh immutable object path before atomically replacing the
  media-row reference, so compensation cannot delete the previous live object;
- delete removes the database reference first; and
- a failed object removal enters the service-role-only
  `storage_cleanup_queue`.

The cleanup routine is unit-tested, the reader e2e verifies unpublish cleanup,
and `pnpm cleanup:media` provides dry-run/apply reconciliation. A broader
inventory check for referenced-but-missing and unreferenced objects remains a
useful periodic operational enhancement.

#### 6. There is no rate limiting or key lifecycle

Bearer keys are long and compared safely, but they are static environment
configuration. There is no request throttling, expiry, rotation overlap,
per-key revocation timestamp, or audit record. This is acceptable for a
private prototype, but not for an internet-facing journal API.

The role definitions correctly restrict `agent`, but configuration also accepts
an arbitrary explicit `scopes` array (`web/src/lib/api/keys.ts:38-48`). That is
useful for advanced deployments, but it bypasses the role guardrail: a GPT key
configured with explicit owner scopes could publish or delete. Key names do not
carry security meaning, so this is a configuration hazard rather than a current
authorization bypass.

Recommendation:

- Store key metadata separately from deployment configuration or support
  multiple active rotation generations deliberately.
- Prefer named roles for production keys. If custom scopes remain supported,
  require an explicit unsafe opt-in and test that agent-purpose configuration
  cannot receive owner or proposal-decision scopes accidentally.
- Record principal, operation, status, request ID, and duration without
  logging content or secrets.
- Add per-key and per-IP limits, especially to invite-token and agent routes.
- Keep the deployed security headers in `netlify.toml` and add a deliberate
  audit-log retention policy if request auditing is introduced.

#### 7. SQL functions need explicit hardening

Write functions are correctly revoked from public roles and granted to
`service_role`. Complete the hardening by using an explicit safe `search_path`
and revoking default execution for every public function, including trigger
helpers. Run Supabase security/performance advisors as part of deployment
review.

#### 8. The OpenAPI contract is route-oriented, not yet client-grade

The owner document verifies that documented paths and methods exist, but most
success response schemas are empty objects and the test does not find
undocumented handlers or validate response bodies
(`web/src/lib/api/owner-openapi.ts:20-24`,
`web/src/lib/api/owner-openapi.test.ts:33-42`).

Recommendation:

- Describe concrete success and error schemas for generated clients.
- Add contract tests that exercise handlers and validate their responses
  against the document.
- Keep the hand-coded Swift payload layer covered as the contract evolves. It
  maps iOS `body` to API `notes`, visibility, translations, narrative-source
  values, stable travel days, and Photos IDs to hashed media keys; outbox tests
  now exercise payload hashing and retry confirmation.
- Include API version compatibility and minimum-client behavior before the app
  depends on production.

### iPhone correctness and UX gaps

#### 9. Automated iOS coverage now protects new persistence work

`JourneyTests` covers stable local-day behavior, durable publishing outbox
transitions, and migration from reconstructed historical SwiftData schemas,
and runs in Xcode 26 CI. `JourneyUITests` remains a demo recording rather than
a regression suite. Visit/photo matching boundaries, tag rules,
narrative-source changes, and translation invalidation still need focused
domain tests.

#### 10. Existing translations silently become stale

Editing title, notes, or narrative does not clear or mark the stored
translation stale. The reader can still switch to an older translation after
the original changes (`ios/Journey/Views/EntryEditorView.swift:395-419`,
`ios/Journey/Views/JournalPageView.swift:109-117`).

Track a translation source fingerprint or clear affected translated fields
when their originals change.

#### 11. Background persistence errors are invisible

Location capture, place naming, and photo-derived visit creation use `try?`
for fetch/save operations
(`ios/Journey/Services/LocationService.swift:55-67`,
`ios/Journey/Services/PhotoPlaces.swift:40-42`,
`ios/Journey/Services/PlaceNamer.swift`). A failed write looks like successful
tracking and may be discovered only after data is missing.

Add structured local diagnostics and a non-intrusive health state in Settings.
Do not include exact coordinates or journal text in logs.

An additional matching edge case needs a test and a policy:
`DayTimeline` treats a visit with no departure as lasting until wall-clock
`now` (`ios/Journey/Services/DayTimeline.swift:29-38`). Because `DayView`
supplies only that day's assets, this does not pull photos from later calendar
days, but an old open-ended visit can absorb unrelated photos taken later on
the same day. Bound an unresolved past visit to the viewed day or a conservative
maximum duration, then resolve overlaps by nearest distance/time rather than
the current first match.

#### 12. City-level locality caching — resolved

The server correctly drops a specific `place_name` at city precision and uses
`location.locality` instead (`web/src/lib/domain/location.ts:49-58`). The iOS
publisher now reverse-geocodes locality for each publish
(`ios/Journey/Services/Publisher.swift:90-103`), which fixes the original
contract gap in the normal case.

`EntryMetadataCache` now stores the last successful structured locality, and
publishing reuses it when geocoding is temporarily unavailable instead of
silently clearing the published city.

#### 13. Permission and missing-media states need first-class UX

Limited Photos access is accepted, Photos may be in iCloud, and assets can be
deleted. Stored identifiers can therefore resolve to nothing. The UI mostly
renders placeholders without explaining whether access, download, or deletion
is the cause.

Show per-entry missing media, allow relinking/removal, and make publish
preflight state explicit. Do not broaden Photos permission automatically.

The publisher deliberately omits videos and explains that choice in the sheet.
It now caches confirmed asset-ID/media-key pairs and preserves an unresolved
remote photo when Photos access or download is temporarily unavailable. The
remaining gap is first-class relink/removal UX that distinguishes the cause of
an unavailable local asset.

### Website product and operational gaps

#### 14. Invitee access boundary — implemented

`/i/[token]` exchanges a valid token for a secure HTTP-only cookie and redirects
to token-free reader pages. Entry and media requests reauthorize against the
database, media uses 90-second signed private-Storage redirects, and revocation
is effective on the next application request. SQL and localhost HTTP tests
cover missing, under-tagged, private, all-tags, signed-media, and revoked cases.

The original bearer token necessarily appears once in the `/i/[token]` request
path under the selected stateless token-cookie design. It is removed from
subsequent browser URLs, but the initial request can still enter provider
access logs. Keep URL logging disabled or tightly retained/redacted;
eliminating that exposure would require a fragment-plus-POST exchange or an
independent server-side session credential.

#### 15. Database and end-to-end CI — implemented

`.github/workflows/web.yml` starts a pinned local Supabase stack, resets all
migrations/seed behavior, runs every SQL test through the portable runner,
builds and starts Next.js with fixed test-only secrets, waits for readiness,
runs owner and reader HTTP suites, and always stops local services.
`.github/workflows/ios.yml` regenerates the project and runs app, unit, and
migration tests on Xcode 26.

#### 16. Operations runbook — implemented

`docs/operations.md` covers Supabase backup/restore drills, migration
forward-fixes, API/service/session-key rotation, destination recovery, invite
incidents, Netlify rollback, media cleanup, privacy-safe logs, smoke checks,
and local CI parity.

## Recommended next functionality

### Set 0: protect the journal first

Completed: stable local days/timezones, versioned migrations and old-store
tests, persistent destination-bound outbox, and documented key/destination
recovery. Remaining: user export/import and visible persistence health.

Exit criterion: existing data survives migration, timezone changes do not move
entries, and a failed save is observable and recoverable.

### Set 1: harden publishing and add the invite reader

Completed: persistent outbox, unresolved-photo preservation, locality cache,
rename propagation, invite exchange/session, reader pages, signed media, and
revoked/under-tagged HTTP authorization coverage.

Exit criterion: a new entry can be published, read by exactly the intended
invite, changed, hidden by revocation, and removed from the server under
network retry.

### Set 2: complete media delivery and reconciliation

Implemented: on-device JPEG export, metadata removal, hashed keys, resumable
uploads, explicit video omission, signed invite reads, durable deletion queue,
operator reconciliation, and full invite/tag media authorization tests.

Remaining:

1. Show partial upload and missing-photo states outside the transient publish
   sheet.
2. Test the Swift and TypeScript JPEG metadata walkers against shared fixtures.
3. Define whether video remains local-only or gains a separate upload contract.

Exit criterion: interrupted upload and delete operations converge without
leaking precise metadata, orphaning inaccessible objects indefinitely, or
showing media to an unauthorized invite.

### Set 3: narration history and agent proposals

1. Add immutable iOS narrative revisions before accepting external text.
2. Build the restricted agent read/proposal API and GPT-compatible OpenAPI
   surface.
3. Base proposals on a complete source revision/fingerprint.
4. Add proposal diff, accept, reject, stale warning, and revert UI.
5. Make acceptance recoverable if the app stops between server decision and
   republishing the accepted text.

Exit criterion: every accepted narrative is attributable and reversible, and
the agent cannot publish, delete, manage invites, or decide proposals.

### Set 4: map and journal quality

1. Add a map over the stable entry/place domain, with clustering and tag/date
   filters.
2. Default published pins to city precision independently of local exact
   coordinates.
3. Add visit correction, merge/split, place rename, and "not a visit" controls.
4. Improve missing-media, permission, and empty-day explanations.
5. Consider search and lightweight trip grouping after map behavior is solid.

The sharing boundary is now implemented, so map work can build on the stable
cross-platform domain when prioritized.

### Set 5: hardening and operations

Completed: SQL and owner/reader HTTP integration CI, iOS migration/unit CI,
key-rotation procedures, backup/restore drills, and deploy/incident runbook.

Remaining:

1. Add rate limiting, request IDs, and redacted audit events before broader use.
2. Add accessibility and localization passes.
3. Add performance tests for large photo libraries, multi-year calendars, and
   hundreds of entries/proposals.

## Verification performed

For the current step-6 tree:

- XcodeGen regeneration was reproducible.
- Xcode 26.6/iOS 26.5 ran 36 `JourneyTests`, including migration and outbox
  suites, with no failures.
- TypeScript typecheck and the Next.js production build passed.
- Vitest ran 62 tests in 12 files with no failures.
- Both workflow files parsed as YAML, script syntax checks passed, and the
  repository diff passed whitespace validation.
- A fresh local database reset, all SQL suites, and the owner HTTP e2e passed
  during implementation. The final reader e2e rerun was blocked because an
  unrelated local Supabase project already occupied Journey's standard ports;
  the complete owner/reader sequence is enforced by web CI on a clean runner.

## Bottom line

The project now has the intended stable-day, migration, durable publishing,
destination recovery, invite-reader, signed-media, integration-CI, and
operations foundations. The largest remaining safety gap is an end-user
archive/backup path; the largest planned product slice is narration history
plus the restricted agent proposal API. Map work can follow without
retrofitting these sharing foundations around live data.
