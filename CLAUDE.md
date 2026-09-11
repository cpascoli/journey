# Journey

Personal iOS travel journal: records place visits, matches the photos and
videos taken at each, and lets the user write entries per day across one or
more journals. See README.md for features and roadmap.

## Build and run

```sh
xcodegen generate
xcodebuild -project Journey.xcodeproj -scheme Journey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- Xcode 26, iOS 26 deployment target, iPhone only, portrait.
- Schemes: `Journey` (app; UI tests with `DemoWalkthrough` skipped) and
  `Journey-Demo` (used only by `Tools/record-demo.sh`).
- There are no automated tests yet. `JourneyUITests` holds only the demo
  walkthrough, which is a recording script, not a test.

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
- Media is never copied: entries store Photos `localIdentifier`s.
- Three tabs: **Write** (`DayView` + `EntryEditorView`, edit mode),
  **Calendar** (`CalendarView` → `JournalPageView` → `MediaViewer`, read mode)
  and **Settings** (journal selection, dictation language, permissions). The
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

## Planned direction

Decisions already made, so new work fits them:

- **Views:** a map view (clustered pins) alongside the calendar.
- **Narration history:** on-device drafting exists (see Code). Still to come:
  a revision history per entry, so ChatGPT proposals can be accepted,
  rejected or reverted to an earlier version.
- **Publishing:** entries get a visibility (local only / private sync /
  public). A separate website exposes an agent-friendly API; a custom GPT uses
  it to read entries and submit narrative *proposals* tied to the revision
  they're based on. The app accepts or rejects them; only accepted text is
  ever public. The GPT's token must not be able to delete or publish.
- A ChatGPT subscription gives no API access, so the app itself never calls
  OpenAI.
