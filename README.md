# Journey

A personal travel journal that fills itself in as you go. The iPhone app
records the places you visit, pairs them with the photos and videos you took
there, and lets you write about each day. Its website publishes only the
entries you choose to the friends and family you invite.

![Journey walkthrough](ios/Docs/demo.gif)

## What's here

| Folder | What it is |
| ------ | ---------- |
| [`ios/`](ios) | The iPhone app: SwiftUI and SwiftData, with on-device AI drafting, dictation and translation. Its [README](ios/README.md) covers building and running it. |
| [`web/`](web) | The website and API, on Netlify: invite-only reading of published entries, an owner dashboard, an API for the app to publish through, and an agent API for a custom GPT. Its [README](web/README.md) covers setup and deployment. |
| [`docs/operations.md`](docs/operations.md) | Backup, restore, migration, secret rotation, incident, rollback, media cleanup, logs, and local-CI procedures. |

## How sharing works

Tags decide who sees what. Each invite is limited to a set of tags: an entry
is shown to an invite only if the invite includes **all** of the entry's
tags, and entries without tags are shown to everyone invited. Either way,
nothing leaves the phone until you publish it. The website enforces the
rules; the app sends each entry's tags along with it.

## Caveats

This is a personal project, not something to ship. It holds a detailed record
of where you've been. Web and iOS CI exercise migrations, policy rules,
publishing/reading integration, and SwiftData migration tests; device-only
features still require a real iPhone.
