import SwiftData
import XCTest

@testable import Journey

@MainActor
final class WebsiteEditTests: XCTestCase {
    private func remote(
        title: String = "Title",
        notes: String = "Notes",
        narrative: String = "Story",
        language: String = "it",
        translatedTitle: String = "Titolo",
        translatedNotes: String = "Appunti",
        translatedNarrative: String = "Storia"
    ) -> RemoteEntryText {
        RemoteEntryText(
            title: title, notes: notes, narrative: narrative,
            translationLanguage: language, translatedTitle: translatedTitle,
            translatedNotes: translatedNotes, translatedNarrative: translatedNarrative
        )
    }

    private func entry(in context: ModelContext) -> Entry {
        let entry = Entry()
        entry.title = "Title"
        entry.body = "Notes"
        entry.narrative = "Story"
        entry.translationLanguage = "it"
        entry.translatedTitle = "Titolo"
        entry.translatedBody = "Appunti"
        entry.translatedNarrative = "Storia"
        context.insert(entry)
        return entry
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testIdenticalTextIsNotADivergence() throws {
        let container = try makeContainer()
        XCTAssertFalse(remote().differs(from: entry(in: container.mainContext)))
    }

    func testEachFieldIsCompared() throws {
        let container = try makeContainer()
        let local = entry(in: container.mainContext)
        XCTAssertTrue(remote(title: "Changed").differs(from: local))
        XCTAssertTrue(remote(notes: "Changed").differs(from: local))
        XCTAssertTrue(remote(narrative: "Changed").differs(from: local))
        XCTAssertTrue(remote(language: "en").differs(from: local))
        XCTAssertTrue(remote(translatedTitle: "Cambiato").differs(from: local))
        XCTAssertTrue(remote(translatedNotes: "Cambiato").differs(from: local))
        XCTAssertTrue(remote(translatedNarrative: "Cambiato").differs(from: local))
    }

    /// The website's `notes` column is the app's `body`, and its
    /// `translated_notes` is `translatedBody`. Getting that mapping wrong would
    /// report a conflict on every entry.
    func testTheNotesColumnMapsToTheAppsBody() throws {
        let container = try makeContainer()
        let local = entry(in: container.mainContext)
        local.body = "Different notes"
        XCTAssertTrue(remote(notes: "Notes").differs(from: local))
        XCTAssertFalse(remote(notes: "Different notes").differs(from: local))
    }

    /// A missing hash is what marks a website edit, so its meaning is pinned.
    func testAMissingContentHashMeansTheWebsiteWasEdited() {
        let edited = RemoteEntryState(mediaKeys: [], clientContentHash: nil)
        let inStep = RemoteEntryState(mediaKeys: [], clientContentHash: String(repeating: "a", count: 64))
        XCTAssertTrue(edited.wasEditedOnWebsite)
        XCTAssertFalse(inStep.wasEditedOnWebsite)
    }

    func testAdoptingTheWebsiteTextReplacesEveryFieldAndQueuesARepublish() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let local = entry(in: context)
        local.localDay = "2026-09-20"
        try context.save()

        let publisher = Publisher(context: context)
        let configuration = URLSessionConfiguration.ephemeral
        let api = JourneyAPI(
            baseURL: URL(string: "https://ashone.example")!,
            key: String(repeating: "k", count: 32),
            session: URLSession(configuration: configuration)
        )
        let website = remote(
            title: "Corrected", notes: "Corrected notes", narrative: "Corrected story",
            language: "it", translatedTitle: "Corretto",
            translatedNotes: "Appunti corretti", translatedNarrative: "Storia corretta"
        )

        try publisher.adoptWebsiteText(website, into: local, api: api)

        XCTAssertEqual(local.title, "Corrected")
        XCTAssertEqual(local.body, "Corrected notes")
        XCTAssertEqual(local.narrative, "Corrected story")
        XCTAssertEqual(local.translatedTitle, "Corretto")
        XCTAssertEqual(local.translatedBody, "Appunti corretti")
        XCTAssertEqual(local.translatedNarrative, "Storia corretta")
        // Words written on the website are the owner's, not an AI draft.
        XCTAssertEqual(local.narrativeSource, .user)
        // Queued so the same words go back and the cleared hash is restored.
        XCTAssertEqual(try context.fetch(FetchDescriptor<PublishOperation>()).count, 1)
        XCTAssertFalse(website.differs(from: local), "adopting should end the divergence")
    }
}
