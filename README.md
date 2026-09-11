# Journey

A personal iOS travel journal that fills itself in as you go: it records the
places you visit, pairs them with the photos and videos you took there, and
lets you write about each day — in one journal or several.

![Journey walkthrough](Docs/demo.gif)

## What it does

- **Records where you go.** Place visits are captured in the background with
  almost no battery cost, and named automatically.
- **Matches your media to places.** Each place in a day shows the photos and
  videos taken there, straight from your library — nothing is copied.
- **A day at a glance.** Your entries, the places you visited and any
  leftover photos, with arrows to move between days.
- **Entries on your terms.** Title, place, time, notes, photos and videos — all
  optional. Tap the pencil on a place and the entry starts pre-filled with it.
  The keyboard's dictation mic works in the notes.
- **More than one journal.** Everything goes to *Main* by default; add others
  from the journal menu when you want them.

### On the way

- **Calendar view** that zooms from year to month, week and day.
- **Map view** with entries as pins that cluster as you zoom out.
- **Dictation button** using on-device speech recognition.
- **Draft narration** written on-device by Apple Intelligence, from each
  entry's places, times, notes and photo labels.
- **Publishing** selected entries to your own website. The site exposes an API
  that a custom ChatGPT GPT can use to read your journal and propose richer
  narration, which you accept or reject in the app.

## How it works

### Recording where you go

[`LocationService`](Journey/Services/LocationService.swift) uses Core
Location's *visit* monitoring rather than continuous GPS. iOS reports each
visit twice — on arrival, then again on departure with the same arrival date —
so visits are keyed by arrival time and updated in place. Unknown times arrive
as `distantPast`/`distantFuture` sentinels and are mapped to "unknown".

The service is created when the app launches, not when a view appears: iOS
relaunches a terminated app in the background to deliver a visit, and there is
no UI at that point.

### Matching photos to places

[`DayTimeline`](Journey/Services/DayTimeline.swift) puts a photo under a
visit when it was taken between ten minutes before arrival and ten minutes
after departure, and — if the photo has a location — within 250 m of the
place. Anything left over is shown under *Other photos & videos*.

Entries store Photos library identifiers, not the media, so a journal stays
small and your library remains the single source of truth.

### Data model

SwiftData, with three models: `Journal`, `Entry` and `Visit`. Every property
has a default and every relationship is optional, which is what CloudKit
requires — iCloud sync can be switched on later without a migration. Entries
already carry the fields publishing will need: a stable ID, the remote ID,
publish state, and how precisely to share the location.

## Running it on your iPhone

### What you need

- A Mac with **Xcode 26** and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`).
- An **iPhone on iOS 26**. Draft narration, when it lands, will need an
  Apple Intelligence iPhone (15 Pro or newer).
- An **Apple ID**. A free one works; the app then has to be reinstalled every
  7 days.

### Steps

1. Sign in to Xcode with your Apple ID (**Xcode → Settings → Accounts**).
2. Edit **`project.yml`**: set `bundleIdPrefix`, `DEVELOPMENT_TEAM`, and the
   two `PRODUCT_BUNDLE_IDENTIFIER`s to your own. A bundle identifier is unique
   across all of Apple, so `com.carlopascoli.journey` can't be reused. To find
   your Team ID:

   ```sh
   security find-identity -v -p codesigning \
     | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1 \
     | xargs -I{} security find-certificate -c "{}" -p \
     | openssl x509 -noout -subject | tr '/' '\n' | grep '^OU=' | cut -d= -f2
   ```

3. Generate the project and open it:

   ```sh
   xcodegen generate
   open Journey.xcodeproj
   ```

4. Plug in your iPhone, pick it in the toolbar and press **⌘R**.
5. The first launch says *Untrusted Developer*: on the phone go to
   **Settings → General → VPN & Device Management**, tap your Apple ID and
   **Trust**.
6. When asked, allow location **Always** (visits are recorded in the
   background) and **Full Access** to photos.

`project.yml` is the source of truth: `xcodegen generate` overwrites the Xcode
project, so change targets and build settings there, not in Xcode's UI. The
source folders are Xcode *synchronised folders*, so a file added under
`Journey/` is picked up without regenerating.

### From the terminal

```sh
xcodegen generate
xcodebuild -project Journey.xcodeproj -scheme Journey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Demo mode

Debug builds launched with `-demo` use an in-memory store seeded with a short
Bangkok trip ([`DemoData`](Journey/Demo/DemoData.swift)), so your real journal
is never touched. The `Journey-Demo` scheme passes the flag for you.

## Regenerating the demo

Run this **by hand**, and only when a change is worth showing. Each recording
commits a new binary, and the GIF stays accurate across most changes.

```sh
Tools/record-demo.sh                          # defaults
SPEEDUP=2 FPS=8 WIDTH=280 KEEP_CAPTURE=1 \
  Tools/record-demo.sh                        # retune the encoding
```

The script erases a dedicated **Journey Demo** simulator (created on first
run), stamps the simulator's sample photos with today's times and the demo
places' coordinates
([`stage-demo-photos.swift`](Tools/stage-demo-photos.swift)), answers the
permission prompts off camera, then records
[`DemoWalkthrough`](JourneyUITests/DemoWalkthrough.swift) and writes
`Docs/demo.gif`. The walkthrough prints wall-clock markers when it starts and
finishes, and the GIF is trimmed to them, so the test runner's slow start-up
never makes it into the file.

[`make-gif.swift`](Tools/make-gif.swift) needs nothing beyond the system
frameworks. It merges identical consecutive frames into one longer frame, which
is what keeps the pauses between steps from bloating the file.

The app icon — a sunset chedi over the Andaman Sea, with dark and tinted
variants — is generated too:

```sh
swift Tools/make-icon.swift
```

## Simulator limits

- The simulator never produces visits; iOS only records them from real
  movement. Test *Places* on a phone.
- On iOS 26, `simctl privacy grant photos` doesn't stop the photo prompt, so
  answer it once by hand.

## Caveats

This is a personal project, not something to ship. It holds a detailed record
of where you've been: it stays on the device until publishing exists, and
publishing will default to city-level locations.
