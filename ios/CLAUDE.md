# Journey — iPhone app

The iPhone app in the Journey monorepo: records place visits, matches the
photos and videos taken at each, and lets the user write entries per day
across one or more journals. See README.md in this folder for features.
Rules shared with the website — tag sharing rules and the planned publishing
design — are in `../CLAUDE.md`.

Paths and commands below are relative to `ios/`.

## Build and run

```sh
xcodegen generate
xcodebuild -project Journey.xcodeproj -scheme Journey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -project Journey.xcodeproj -scheme Journey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:JourneyTests CODE_SIGNING_ALLOWED=NO
```

- Xcode 26, iOS 26 deployment target, iPhone only, portrait.
- Schemes: `Journey` (app; UI tests with `DemoWalkthrough` skipped) and
  `Journey-Demo` (used only by `Tools/record-demo.sh`).
- `JourneyTests` contains unit and store-migration tests. `JourneyUITests`
  holds only the demo walkthrough, which is a recording script, not a test.

## Project file

- `project.yml` (XcodeGen) is the source of truth. `Journey.xcodeproj` is
  generated and committed; never edit it or its schemes by hand — change
  `project.yml` and run `xcodegen generate`.
- Both source folders are `syncedFolder`s, so adding or removing files under
  `Journey/` or `JourneyUITests/` needs no regeneration. New targets, build
  settings, schemes or Info.plist keys do.
- Info.plist is generated from `INFOPLIST_KEY_*` build settings in
  `project.yml` (usage descriptions live there).
- XcodeGen's iOS presets override project-level settings: e.g. they set
  `TARGETED_DEVICE_FAMILY` to `1,2`, so iPhone-only is pinned per target.
  Check `xcodebuild -showBuildSettings` after changing settings.
- Bundle IDs: `com.carlopascoli.journey` and `com.carlopascoli.journey.uitests`.
  `Tools/record-demo.sh` hard-codes the app's ID for permission grants.

## Code

- Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  approachable concurrency: everything is main-actor by default. Delegate
  callbacks from system frameworks are `nonisolated` and hop back with
  `Task { @MainActor in … }` (see `LocationService`).
- SwiftData models must stay CloudKit-compatible: every stored property has a
  default, relationships are optional, no `@Attribute(.unique)`. Store enums as
  raw strings with a computed accessor (see `Entry.publishStatus`).
- **The user has real journal data on their phone: model changes must never
  lose it.** The store has no `VersionedSchema`, and relies on SwiftData's
  automatic lightweight migration, so only make additive changes: new stored
  properties with a default value, new models, new optional relationships.
  Never rename, remove or retype a stored property, or change a relationship's
  shape, without first introducing a `VersionedSchema` + `SchemaMigrationPlan`.
  Before shipping a model change, prove it: build the oldest shipped commit
  (`648691b`, the first with bundle ID `com.carlopascoli.journey`), create data
  with it on a simulator, install the new build over it, and check the data is
  still there.
- Media is never copied: entries store Photos `localIdentifier`s. Their order
  is the order of `mediaAssetIDs`, which the website turns into `sort_order`,
  so reordering republishes without re-uploading. The editor lists them as
  ordinary rows with `.onDelete` and `.onMove`, so removing and reordering
  behave as they do in any list. An earlier drag-and-drop grid is gone: its
  overlay delete button shared a view with a drag gesture, which made taps
  unreliable.
- Tags (`Tag`, many-to-many with `Entry`, shared across journals) are also
  the website's sharing rules — read `../CLAUDE.md` before changing how they're
  stored or deleted. In the app, a tag that's in use can't be deleted, and
  tags are referenced by `id`, so renames are safe.
- Four tabs: **Write** (`DayView` + `EntryEditorView`, edit mode),
  **Calendar** (`CalendarView` → `JournalPageView` → `MediaViewer`, read mode),
  **Sharing** (`SharingView` → invitations and reader comments) and
  **Settings** (journal selection, dictation language, permissions). The
  active journal shows as a navigation subtitle once there's more than one.
  Write must stay the first tab; `DemoWalkthrough` expects to land on it.
  Calendar scales zoom in by tapping (year → month, week/month → day page).
- `DayTimeline` owns the photo-to-visit matching rule (±10 min around the
  visit, and ≤250 m when the photo has a location).
- `Visit.source` is `.tracked` (Core Location) or `.photos` (rebuilt by
  `PhotoPlaces` from the day's unmatched located photos when the day opens).
  `PhotoPlaces.radius` is `DayTimeline.maxDistance` on purpose: if clustering
  were looser than matching, a photo could miss its own visit and spawn a new
  one on every open.
- All reverse geocoding goes through `PlaceNamer` (sequential, paced — Apple
  throttles it); unnamed visits are retried whenever their day is opened.
- `CLGeocoder` is deprecated on iOS 26; reverse geocoding uses
  `MKReverseGeocodingRequest`.
- AI drafting: `PhotoLabeler` (Vision `ClassifyImageRequest`) turns media into
  labels, because the Foundation Models system model is text-only;
  `NarrativeDrafter` streams a draft into `Entry.narrative`. AI writes only to
  `narrative`, never to `body` (the user's notes). `narrativeSource` records
  who wrote it; an edited AI draft becomes `.user`. Keep prompts short — the
  model's context window is small, so draft one entry at a time.
- Drafting can't be exercised in this Mac's simulator (macOS 15 host); it needs
  a device with Apple Intelligence or a macOS 26 host. When unavailable the
  button is disabled and the footer shows `NarrativeDrafter.unavailableReason`.
- Dictation: `Dictation` wraps iOS 26 `SpeechAnalyzer` + `DictationTranscriber`
  (`AssetInventory` downloads each language's model on first use). The mic tap
  and buffer conversion are `nonisolated static` on purpose — Core Audio calls
  them off the main thread, and everything else is main-actor. Final results
  are appended to the focused field; volatile ones only show in the keyboard
  bar.
- Translation: `EntryTranslator` runs through the SwiftUI `.translationTask`
  modifier, which owns the language-download prompt. Results live in
  `Entry.translated*` + `translationLanguage`, never over the originals.
- `PHPickerFilter` has no date option, hence `DayPhotoPicker` for the entry's
  day; the system `PhotosPicker` remains as *Browse All Photos*.
- Drafting, dictation and translation all need on-device models: verify them
  on a phone.

## Publishing

- `JourneyAPI` is the client for the website's owner API. The contract is
  `../web/src/lib/api/owner-openapi.ts`: change both together.
- `Publisher` sends the entry's tags first (entries refer to them by `id`),
  then the entry with its full ordered `media_keys`, then only the photos the
  website reports missing, so publishing again is safe and resumes uploads.
- The website URL is in UserDefaults (`websiteURL`, https only); the owner key
  is in the Keychain, this device only. Never log it or put it in a URL.
- Photos leave the phone only through `PhotoExport`: re-encoded at up to
  2048 px with the orientation baked in, then APP1 (EXIF, XMP), APP13 (IPTC)
  and comment segments stripped. `JPEGMetadata` mirrors the website's
  `findPhotoMetadata`; keep them in step, and never rely on the server to strip.
- `PhotoExport.thumbnail` makes the 480px copy the website's grid shows,
  stripped exactly as the full image is. It uploads separately and only for
  keys the website reports as lacking one, so republishing an older entry
  gains thumbnails without re-sending the photos. A failed thumbnail never
  fails a publish: the website falls back to the full image.
- Videos leave only through `VideoExport`: H.264 at 720p, `metadata = []` to
  drop the QuickTime location atoms, and `shouldOptimizeForNetworkUse = true`.
  That last flag is a requirement, not a tuning knob — the website verifies an
  upload by reading only the head of the file and refuses one whose `moov` is
  not at the front. Caps are 90 seconds and 60 MB (the website's
  `MAX_VIDEO_BYTES`); `MediaKeyTests` pins them to the contract.
- Videos are exported *before* `media_keys` is built, not during the upload
  loop: a clip that turns out too large has to be left out of that list, and by
  upload time it is already committed. Only videos the website has not
  confirmed are exported, so re-publishing re-encodes nothing.
- `MediaKey` is the one key derivation for both kinds (SHA-256 of the Photos
  identifier). Changing it orphans every published item, so it is pinned by a
  test. `MediaAvailability.skipped` means "deliberately left off" and must
  never fall back to a confirmed key, unlike `.unavailable`.
- A video goes straight from the phone to the object store with a signed URL
  (`JourneyAPI.putVideo`), because a Netlify request body caps at 6 MB. The
  owner key is never sent to the store.
- `PublishSheet` saves visibility and location precision only when *Publish*
  is tapped: a wider audience never takes effect implicitly. Precision
  `hidden` sends no location at all.
- Sharing lives in its own tab, not in Settings: it is used regularly, while
  settings are set once. `DemoWalkthrough` taps tabs by label, so tab order
  can change, but Write must stay first.
- `InviteLinks` remembers each invitation link this phone issues, so one can
  be shared again without breaking the old one. Only the **token** is kept,
  in the Keychain (this device only), and the URL is rebuilt from the current
  website — so a remembered link survives the journal changing domain. The
  index of which invitations have a token is in UserDefaults, which is what
  makes `prune` possible; revoking forgets the token rather than leaving the
  secret behind. A test bundle has no Keychain entitlement, so the store is
  injectable (`InviteSecretStore`).
- The invite detail always offers a share affordance: the remembered link when
  there is one, otherwise a button that issues one. An invitation created
  before this existed, or on another phone, has no remembered token — the
  website stores only a hash — so sharing it means issuing a new link, and
  the wording says so rather than letting it surprise.
- `InviteManagementView` lists invitations; tapping one opens its detail, where
  the allowed tags are saved as a whole set and the link can be replaced. Tag
  edits are not applied until *Save*, so widening access is always deliberate,
  and the row shows how many entries the invitation actually reads (from the
  website — the all-tags rule is too easy to misjudge by hand).
- `CommentInbox` holds the unread comment count behind the Sharing tab's
  badge. It refreshes when the app reaches the foreground, not on a timer:
  comments arrive over days, so polling would spend battery to learn nothing.
  The count is persisted, so the badge is right at launch and a failed
  refresh leaves it alone rather than claiming nothing is waiting.
- `CommentsView` lists reader conversations (Sharing → Comments).
  Each is private to one invitation, so one entry can show several threads;
  opening a thread is what marks it read. Only the owner can delete a comment.
- Publishing is one-way, with one exception: the website clears
  `client_content_hash` when its text is edited there, so
  `Publisher.websiteEdit` can tell that the website holds words the app never
  sent. `PublishSheet` then shows when it changed, offers a field-by-field
  review, and makes publishing confirm before replacing it.
  `adoptWebsiteText` takes the website's words and republishes them, which
  restores the hash — otherwise the entry would look edited forever. The
  website's `notes` is the app's `body`, and `translated_notes` is
  `translatedBody`; get that mapping wrong and every entry looks changed.
- A published entry, or a journal holding one, can't be deleted in the app:
  unpublish first, or it would stay online. Tag renames reach the website at
  the next publish of an entry that uses the tag.

## Demo and tools

- `-demo` (Debug only) swaps in an in-memory store seeded by
  `Journey/Demo/DemoData.swift`. Its visit schedule must match the shots in
  `Tools/stage-demo-photos.swift`, or the demo photos won't land on places.
- `Tools/record-demo.sh` erases and reuses a simulator named **Journey Demo** —
  never point it at another device. Only run it when asked: it commits a new
  `Docs/demo.gif` binary each time.
- `Tools/make-icon.swift` regenerates the three `AppIcon` variants into the
  asset catalog.

## Simulator gotchas

- The first boot of a newly installed runtime can fail with *Mach error -308
  (server died)*; booting again works.
- `simctl privacy grant photos` is ignored on iOS 26 — the prompt still shows.
  A prompt that appears mid-UI-test is answered "Don't Allow" by XCTest's
  default handler, so `testGrantPermissions` registers an interruption monitor
  and runs before recording, and `record-demo.sh` checks TCC.db and stops if
  photos aren't granted.
- The simulator never produces `CLVisit`s; use demo mode, or a real device.
- To tap inside the simulator from a script, System Events `click at` fails
  (-25204); post `CGEvent` mouse events instead. The phone screen is the
  Simulator window's `AXGroup` element, 1:1 in points.
