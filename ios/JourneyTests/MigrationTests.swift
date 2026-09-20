import CoreLocation
import SwiftData
import XCTest
@testable import Journey

@MainActor
final class MigrationTests: XCTestCase {
    private struct Snapshot {
        let narrative: String
        let visitSource: String?
        let tagNames: [String]
        let visibility: String
        let remoteID: String?
    }

    private struct FixtureExpectation {
        let resource: String
        let id: UUID
        let title: String
        let body: String
        let journalName: String
        var mediaAssetIDs: [String] = []
        var visitPlaceName: String?
        var narrative = ""
        var narrativeSource = "user"
        var translationLanguage = ""
        var translatedTitle = ""
        var visitSource = "tracked"
        var tagName: String?
        var tagColor: String?
        var visibility = "private"
        var publishStatus = "notPublished"
        var remoteID: String?
    }

    private let instant = Date(timeIntervalSince1970: 1_757_877_000)

    func testHistoricalShippedStoreFixturesUpgradeToCurrentSchema() throws {
        let fixtures = [
            FixtureExpectation(
                resource: "v1-original",
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "Historical V1",
                body: "Synthetic original notes",
                journalName: "Fixture Original",
                mediaAssetIDs: ["synthetic-asset-v1"],
                visitPlaceName: "Synthetic Place"
            ),
            FixtureExpectation(
                resource: "v2-narrative",
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                title: "Historical V2",
                body: "Synthetic narrative notes",
                journalName: "Fixture Narrative",
                narrative: "Synthetic preserved story",
                narrativeSource: "onDevice",
                translationLanguage: "it",
                translatedTitle: "Storico V2",
                visitSource: "photos"
            ),
            FixtureExpectation(
                resource: "v3-tags",
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                title: "Historical V3",
                body: "Synthetic tagged notes",
                journalName: "Fixture Tags",
                tagName: "Synthetic Tag",
                tagColor: "teal"
            ),
            FixtureExpectation(
                resource: "v4-publishing",
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                title: "Historical V4",
                body: "Synthetic publishing notes",
                journalName: "Fixture Publishing",
                tagName: "Synthetic Published Tag",
                tagColor: "indigo",
                visibility: "shared",
                publishStatus: "published",
                remoteID: "synthetic-remote-id"
            ),
        ]

        for fixture in fixtures {
            try XCTContext.runActivity(named: fixture.resource) { _ in
                try assertHistoricalFixture(fixture)
            }
        }
    }

    func testDirectUpgradeFromOriginalUnversionedStore() throws {
        let url = storeURL()
        do {
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: JourneySchemaV1.Journal.self,
                JourneySchemaV1.Entry.self,
                JourneySchemaV1.Visit.self,
                configurations: configuration
            )
            let journal = JourneySchemaV1.Journal(name: "Original")
            let entry = JourneySchemaV1.Entry()
            entry.id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            entry.title = "V1 entry"
            entry.body = "Original notes"
            entry.date = instant
            entry.journal = journal
            let visit = JourneySchemaV1.Visit(
                arrival: instant,
                coordinate: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)
            )
            entry.visits = [visit]
            container.mainContext.insert(journal)
            container.mainContext.insert(entry)
            container.mainContext.insert(visit)
            try container.mainContext.save()
        }
        try assertUpgradedStore(at: url, title: "V1 entry", journalName: "Original")
    }

    func testDirectUpgradeFromNarrativeUnversionedStore() throws {
        let url = storeURL()
        do {
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: JourneySchemaV2.Journal.self,
                JourneySchemaV2.Entry.self,
                JourneySchemaV2.Visit.self,
                configurations: configuration
            )
            let journal = JourneySchemaV2.Journal(name: "Narrative")
            let entry = JourneySchemaV2.Entry()
            entry.title = "V2 entry"
            entry.body = "V2 notes"
            entry.narrative = "Keep this story"
            entry.date = instant
            entry.journal = journal
            let visit = JourneySchemaV2.Visit(
                arrival: instant,
                coordinate: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)
            )
            visit.sourceRaw = "photos"
            entry.visits = [visit]
            container.mainContext.insert(journal)
            container.mainContext.insert(entry)
            container.mainContext.insert(visit)
            try container.mainContext.save()
        }
        let upgraded = try assertUpgradedStore(at: url, title: "V2 entry", journalName: "Narrative")
        XCTAssertEqual(upgraded.narrative, "Keep this story")
        XCTAssertEqual(upgraded.visitSource, "photos")
    }

    func testDirectUpgradeFromTagsUnversionedStore() throws {
        let url = storeURL()
        do {
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: JourneySchemaV3.Journal.self,
                JourneySchemaV3.Entry.self,
                JourneySchemaV3.Visit.self,
                JourneySchemaV3.Tag.self,
                configurations: configuration
            )
            let journal = JourneySchemaV3.Journal(name: "Tagged")
            let entry = JourneySchemaV3.Entry()
            entry.title = "V3 entry"
            entry.body = "V3 notes"
            entry.date = instant
            entry.journal = journal
            let visit = JourneySchemaV3.Visit(
                arrival: instant,
                coordinate: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)
            )
            let tag = JourneySchemaV3.Tag(name: "Food")
            entry.visits = [visit]
            entry.tags = [tag]
            container.mainContext.insert(journal)
            container.mainContext.insert(entry)
            container.mainContext.insert(visit)
            container.mainContext.insert(tag)
            try container.mainContext.save()
        }
        let upgraded = try assertUpgradedStore(at: url, title: "V3 entry", journalName: "Tagged")
        XCTAssertEqual(upgraded.tagNames, ["Food"])
    }

    func testDirectUpgradeFromPublishingUnversionedStore() throws {
        let url = storeURL()
        do {
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: JourneySchemaV4.Journal.self,
                JourneySchemaV4.Entry.self,
                JourneySchemaV4.Visit.self,
                JourneySchemaV4.Tag.self,
                configurations: configuration
            )
            let journal = JourneySchemaV4.Journal(name: "Published")
            let entry = JourneySchemaV4.Entry()
            entry.title = "V4 entry"
            entry.body = "V4 notes"
            entry.date = instant
            entry.visibilityRaw = "shared"
            entry.remoteID = "remote-entry"
            entry.journal = journal
            let visit = JourneySchemaV4.Visit(
                arrival: instant,
                coordinate: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)
            )
            entry.visits = [visit]
            container.mainContext.insert(journal)
            container.mainContext.insert(entry)
            container.mainContext.insert(visit)
            try container.mainContext.save()
        }
        let upgraded = try assertUpgradedStore(at: url, title: "V4 entry", journalName: "Published")
        XCTAssertEqual(upgraded.visibility, "shared")
        XCTAssertEqual(upgraded.remoteID, "remote-entry")
    }

    func testUpgradeFromFrozenLocalDaySchemaToOutboxSchema() throws {
        let url = storeURL()
        do {
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: Schema(versionedSchema: JourneySchemaV5.self),
                configurations: configuration
            )
            let journal = JourneySchemaV5.Journal(name: "Local Day")
            let entry = JourneySchemaV5.Entry()
            entry.title = "V5 entry"
            entry.body = "V5 notes"
            entry.date = instant
            entry.localDay = "2025-09-14"
            entry.timeZoneIdentifier = "Asia/Bangkok"
            entry.journal = journal
            let visit = JourneySchemaV5.Visit(
                arrival: instant,
                coordinate: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018)
            )
            visit.localDay = "2025-09-14"
            visit.timeZoneIdentifier = "Asia/Bangkok"
            entry.visits = [visit]
            container.mainContext.insert(journal)
            container.mainContext.insert(entry)
            container.mainContext.insert(visit)
            try container.mainContext.save()
        }

        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: configuration
        )
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(entry.title, "V5 entry")
        XCTAssertEqual(entry.localDay, "2025-09-14")
        XCTAssertEqual(entry.timeZoneIdentifier, "Asia/Bangkok")
        XCTAssertNil(entry.publishDestinationID)
    }

    func testUpgradeFromOutboxSchemaAddsMetadataCacheModel() throws {
        let url = storeURL()
        let entryID = UUID()
        do {
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: Schema(versionedSchema: JourneySchemaV6.self),
                configurations: configuration
            )
            let journal = Journal(name: "V6")
            let entry = Entry()
            entry.id = entryID
            entry.title = "Preserved"
            entry.journal = journal
            container.mainContext.insert(journal)
            container.mainContext.insert(entry)
            try container.mainContext.save()
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Entry>()).first?.id, entryID)
        let cache = try EntryMetadataCache.findOrCreate(for: entryID, in: container.mainContext)
        cache.locality = "Bangkok"
        try container.mainContext.save()
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<EntryMetadataCache>()).first?.locality,
            "Bangkok"
        )
    }

    @discardableResult
    private func assertUpgradedStore(at url: URL, title: String, journalName: String) throws -> Snapshot {
        let expectedDay = LocalDay.string(for: instant, timeZone: .current)
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: configuration
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<Entry>())
        let visits = try container.mainContext.fetch(FetchDescriptor<Visit>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(visits.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.title, title)
        XCTAssertEqual(entry.body, title.replacingOccurrences(of: "entry", with: "notes")
            .replacingOccurrences(of: "V1 notes", with: "Original notes"))
        XCTAssertEqual(entry.journal?.name, journalName)
        XCTAssertEqual(entry.localDay, expectedDay)
        XCTAssertEqual(entry.timeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(visits.first?.localDay, expectedDay)
        XCTAssertEqual(visits.first?.timeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(entry.visits?.first?.id, visits.first?.id)
        XCTAssertNil(entry.publishDestinationID)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).isEmpty)
        return Snapshot(
            narrative: entry.narrative,
            visitSource: entry.visits?.first?.sourceRaw,
            tagNames: (entry.tags ?? []).map(\.name),
            visibility: entry.visibilityRaw,
            remoteID: entry.remoteID
        )
    }

    private func assertHistoricalFixture(_ expected: FixtureExpectation) throws {
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: expected.resource, withExtension: "store")
        )
        let url = storeURL()
        try FileManager.default.copyItem(at: source, to: url)
        let container = try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<Entry>())
        let visits = try container.mainContext.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(entries.count, 1, expected.resource)
        XCTAssertEqual(visits.count, 1, expected.resource)

        let entry = try XCTUnwrap(entries.first)
        let visit = try XCTUnwrap(visits.first)
        XCTAssertEqual(entry.id, expected.id)
        XCTAssertEqual(entry.title, expected.title)
        XCTAssertEqual(entry.body, expected.body)
        XCTAssertEqual(entry.date, instant)
        XCTAssertEqual(entry.journal?.name, expected.journalName)
        XCTAssertEqual(entry.mediaAssetIDs, expected.mediaAssetIDs)
        XCTAssertEqual(visit.placeName, expected.visitPlaceName)
        XCTAssertEqual(entry.narrative, expected.narrative)
        XCTAssertEqual(entry.narrativeSourceRaw, expected.narrativeSource)
        XCTAssertEqual(entry.translationLanguage, expected.translationLanguage)
        XCTAssertEqual(entry.translatedTitle, expected.translatedTitle)
        XCTAssertEqual(visit.sourceRaw, expected.visitSource)
        XCTAssertEqual(visit.latitude, 13.7563, accuracy: 0.000_001)
        XCTAssertEqual(visit.longitude, 100.5018, accuracy: 0.000_001)
        XCTAssertEqual(entry.visits?.first?.id, visit.id)
        XCTAssertEqual(entry.tags?.first?.name, expected.tagName)
        XCTAssertEqual(entry.tags?.first?.colorName, expected.tagColor)
        XCTAssertEqual(entry.visibilityRaw, expected.visibility)
        XCTAssertEqual(entry.publishStatusRaw, expected.publishStatus)
        XCTAssertEqual(entry.remoteID, expected.remoteID)

        let expectedDay = LocalDay.string(for: instant, timeZone: .current)
        XCTAssertEqual(entry.localDay, expectedDay)
        XCTAssertEqual(entry.timeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(visit.localDay, expectedDay)
        XCTAssertEqual(visit.timeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertNil(entry.publishDestinationID)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<EntryMetadataCache>()).isEmpty)
    }

    private func storeURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "JourneyMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appending(path: "default.store")
    }
}
