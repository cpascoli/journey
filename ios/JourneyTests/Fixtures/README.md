# Historical SwiftData stores

These stores contain synthetic test data only. They exercise the four distinct
unversioned model shapes that shipped with bundle ID
`com.carlopascoli.journey` before `JourneySchemaV5` introduced versioning:

- `v1-original.store` — `648691b772e0abc1fc8b96a8ecadbce8c940e0ce`
- `v2-narrative.store` — `735a71efe0a085cfefa0b44caa5fe78b3222ae35`
- `v3-tags.store` — `9153772f9aa1661655a36054349f2e2b937de52b`
- `v4-publishing.store` — `d79952d1bb1bf3bc0cd41590c303fb1789f1b440`

Commits between these points did not change the persistent model. Git history
was inspected across both the pre-monorepo `Journey/Models` path and the later
`ios/Journey/Models` path.

## Generation

Each commit was checked out detached in a temporary `git worktree`; history was
not rewritten. Historical simulator app builds were also compiled successfully.
The committed fixtures were produced by temporary command-line helpers compiled
with the unchanged historical model files and `-module-name Journey`, for
example:

```sh
swiftc -swift-version 5 -parse-as-library -module-name Journey \
  -o FixtureGenerator FixtureGenerator.swift \
  Journey/Models/Journal.swift Journey/Models/Entry.swift \
  Journey/Models/Visit.swift Journey/Models/Tag.swift \
  -framework SwiftData -framework CoreLocation
./FixtureGenerator /path/to/fixture-directory
```

The helper creates `ModelContainer(for: ...)` from that commit's concrete model
types, writes the UUIDs and values asserted in `MigrationTests.swift`, and saves
`default.store`. No reconstructed `VersionedSchema` participates in fixture
creation. After the writer exits, run:

```sh
sqlite3 default.store 'PRAGMA wal_checkpoint(TRUNCATE); VACUUM;'
sqlite3 default.store 'PRAGMA integrity_check;'
```

Discard the empty `-wal` and `-shm` files and rename the compact store to the
fixture name above. SwiftData metadata contains generated identifiers, so a
regenerated store need not be byte-for-byte identical; the migration test is
the reproducibility check for its model checksum and representative data.
