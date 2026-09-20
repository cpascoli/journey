import Foundation
import SwiftData
import XCTest
@testable import Journey

@MainActor
final class PublishingOutboxTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testTimeoutLeavesDurableIntentAndRestartRetriesIt() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        let payload = try await Publisher.payload(for: entry, mediaKeys: []).addingContentHash()
        let expectedHash = try XCTUnwrap(payload.clientContentHash)
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                throw URLError(.timedOut)
            }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }

        do {
            _ = try await Publisher(context: container.mainContext).publish(entry, with: api)
            XCTFail("Expected the timed-out publish to remain queued")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }

        var operations = try container.mainContext.fetch(FetchDescriptor<PublishOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].entryID, entry.id)
        XCTAssertEqual(entry.publishStatus, .needsUpdate)
        XCTAssertNotNil(entry.publishDestinationID)
        XCTAssertFalse(operations[0].lastError.isEmpty)

        operations[0].nextAttemptAt = .distantPast
        try container.mainContext.save()
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                return Self.response(request, status: 200, body: #"{"missing_media":[]}"#)
            }
            return Self.response(
                request,
                status: 200,
                body: #"{"entry":{"client_content_hash":"\#(expectedHash)","media":[]}}"#
            )
        }

        // A new service instance represents relaunch/foreground recovery.
        await Publisher(context: container.mainContext).processPending(with: api)
        operations = try container.mainContext.fetch(FetchDescriptor<PublishOperation>())
        XCTAssertTrue(operations.isEmpty)
        XCTAssertEqual(entry.publishStatus, .published)
    }

    func testOutboxSurvivesStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "JourneyOutboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")
        let operationID = UUID()

        do {
            let container = try makeContainer(at: url)
            let destination = PublishDestination(baseURL: "https://journal.example", keyFingerprint: "digest")
            let operation = PublishOperation(
                entryID: UUID(),
                destinationID: destination.id,
                kind: .publish,
                requestedEntryUpdate: .now
            )
            operation.id = operationID
            container.mainContext.insert(destination)
            container.mainContext.insert(operation)
            try container.mainContext.save()
        }

        let reopened = try makeContainer(at: url)
        let operations = try reopened.mainContext.fetch(FetchDescriptor<PublishOperation>())
        XCTAssertEqual(operations.map(\.id), [operationID])
        XCTAssertEqual(operations.first?.kind, .publish)
    }

    func testTimedOutPutWithStaleSameMediaGETRemainsQueued() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                throw URLError(.timedOut)
            }
            return Self.response(
                request,
                status: 200,
                body: #"{"entry":{"client_content_hash":"\#(String(repeating: "0", count: 64))","media":[]}}"#
            )
        }

        do {
            _ = try await Publisher(context: container.mainContext).publish(entry, with: api)
            XCTFail("Expected stale server content to leave the publish queued")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }

        XCTAssertEqual(entry.publishStatus, .needsUpdate)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).count, 1)
    }

    func testTimedOutPutWithMatchingHashReconciles() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        let payload = try await Publisher.payload(for: entry, mediaKeys: []).addingContentHash()
        let expectedHash = try XCTUnwrap(payload.clientContentHash)
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                throw URLError(.timedOut)
            }
            return Self.response(
                request,
                status: 200,
                body: #"{"entry":{"client_content_hash":"\#(expectedHash)","media":[]}}"#
            )
        }

        _ = try await Publisher(context: container.mainContext).publish(entry, with: api)

        XCTAssertEqual(entry.publishStatus, .published)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).isEmpty)
    }

    func testTimedOutDeleteReconcilesAsRemoved() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        let getCount = LockedValue(0)
        let payload = try await Publisher.payload(for: entry, mediaKeys: []).addingContentHash()
        let expectedHash = try XCTUnwrap(payload.clientContentHash)
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                return Self.response(request, status: 200, body: #"{"missing_media":[]}"#)
            }
            if request.httpMethod == "DELETE" {
                throw URLError(.timedOut)
            }
            let count = getCount.withValue {
                $0 += 1
                return $0
            }
            if count <= 2 {
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"entry":{"client_content_hash":"\#(expectedHash)","media":[]}}"#
                )
            }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }
        let publisher = Publisher(context: container.mainContext)
        _ = try await publisher.publish(entry, with: api)

        try await publisher.unpublish(entry, with: api)

        XCTAssertEqual(entry.publishStatus, .notPublished)
        XCTAssertNil(entry.publishDestinationID)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).isEmpty)
    }

    func testBoundEntryRejectsAnotherDestination() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" { throw URLError(.timedOut) }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }
        _ = try? await Publisher(context: container.mainContext).publish(entry, with: api)
        let other = JourneyAPI(baseURL: URL(string: "https://other.example")!, key: api.key, session: api.session)

        do {
            _ = try await Publisher(context: container.mainContext).publish(entry, with: other)
            XCTFail("Expected destination guard")
        } catch let error as PublishingError {
            guard case .differentDestination = error else {
                return XCTFail("Unexpected publishing error: \(error)")
            }
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).count, 1)
    }

    func testLatestUpdateCoalescesIntoExistingOperation() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" { throw URLError(.timedOut) }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }
        let publisher = Publisher(context: container.mainContext)
        _ = try? await publisher.publish(entry, with: api)
        entry.title = "Newest title"
        entry.updatedAt = entry.updatedAt.addingTimeInterval(10)
        let newestUpdate = entry.updatedAt
        _ = try? await publisher.publish(entry, with: api)

        let operations = try container.mainContext.fetch(FetchDescriptor<PublishOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].requestedEntryUpdate, newestUpdate)
    }

    func testQueuedPublishBecomesDeletionTombstoneIfEntryDisappears() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let api = makeAPI()
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" { throw URLError(.timedOut) }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }
        _ = try? await Publisher(context: container.mainContext).publish(entry, with: api)
        let entryID = entry.id
        container.mainContext.delete(entry)
        try container.mainContext.save()
        let operation = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PublishOperation>()).first)
        XCTAssertEqual(operation.entryID, entryID)
        operation.nextAttemptAt = .distantPast
        try container.mainContext.save()

        let deleted = LockedValue(false)
        TestURLProtocol.handler = { request in
            if request.httpMethod == "DELETE" {
                deleted.withValue { $0 = true }
                return Self.response(request, status: 200, body: #"{"deleted":true}"#)
            }
            if request.httpMethod == "GET", !deleted.withValue({ $0 }) {
                return Self.response(request, status: 200, body: #"{"entry":{"media":[]}}"#)
            }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }

        await Publisher(context: container.mainContext).processPending(with: api)

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).isEmpty)
    }

    func testContentHashIsDeterministicAndExcludesItself() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let payload = await Publisher.payload(for: entry, mediaKeys: ["photo-key"])
        let first = try payload.addingContentHash()
        var alreadyHashed = payload
        alreadyHashed.clientContentHash = String(repeating: "f", count: 64)
        let second = try alreadyHashed.addingContentHash()

        XCTAssertEqual(first.clientContentHash, second.clientContentHash)

        entry.title = "Changed"
        let changed = try await Publisher.payload(for: entry, mediaKeys: ["photo-key"]).addingContentHash()
        XCTAssertNotEqual(first.clientContentHash, changed.clientContentHash)
    }

    func testUnavailableConfirmedPhotoIsPreserved() {
        let resolved = Publisher.resolvedMedia(
            currentAssetIDs: ["available", "icloud"],
            availability: ["available": .photo(key: "new-key"), "icloud": .unavailable],
            confirmed: ["icloud": "confirmed-key"]
        )

        XCTAssertEqual(resolved.map(\.assetID), ["available", "icloud"])
        XCTAssertEqual(resolved.map(\.key), ["new-key", "confirmed-key"])
    }

    func testIntentionalPhotoRemovalDropsConfirmedMedia() {
        let resolved = Publisher.resolvedMedia(
            currentAssetIDs: ["kept"],
            availability: ["kept": .photo(key: "kept-key")],
            confirmed: ["kept": "kept-key", "removed": "removed-key"]
        )

        XCTAssertEqual(resolved.map(\.key), ["kept-key"])
    }

    func testVideoIsPublishedInTheEntryOrderAlongsidePhotos() {
        let resolved = Publisher.resolvedMedia(
            currentAssetIDs: ["photo", "video"],
            availability: ["photo": .photo(key: "photo-key"), "video": .video(key: "video-key")],
            confirmed: [:]
        )

        XCTAssertEqual(resolved.map(\.assetID), ["photo", "video"])
        XCTAssertEqual(resolved.map(\.key), ["photo-key", "video-key"])
    }

    /// A video too long or too large to export must be left out of media_keys
    /// entirely. Falling back to a confirmed key would promise the website a
    /// file that is never uploaded, and publishing would never confirm.
    func testSkippedMediaIsExcludedEvenIfPreviouslyConfirmed() {
        let resolved = Publisher.resolvedMedia(
            currentAssetIDs: ["video"],
            availability: ["video": .skipped],
            confirmed: ["video": "stale-key"]
        )

        XCTAssertTrue(resolved.isEmpty)
    }

    /// Distinct from skipping: media that is merely unreadable right now (in
    /// iCloud, or outside a limited selection) keeps its confirmed key.
    func testUnavailableVideoKeepsItsConfirmedKey() {
        let resolved = Publisher.resolvedMedia(
            currentAssetIDs: ["video"],
            availability: ["video": .unavailable],
            confirmed: ["video": "confirmed-key"]
        )

        XCTAssertEqual(resolved.map(\.key), ["confirmed-key"])
    }

    func testV7CacheRecoversUnavailableServerPhotoBeforePut() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let assetID = "unavailable-photo-\(UUID().uuidString)"
        let key = PhotoExport.key(for: assetID)
        entry.mediaAssetIDs = [assetID]
        entry.publishStatus = .published
        entry.publishedAt = .now
        let payload = try await Publisher.payload(for: entry, mediaKeys: [key]).addingContentHash()
        let expectedHash = try XCTUnwrap(payload.clientContentHash)
        let api = makeAPI()
        let getCount = LockedValue(0)
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                return Self.response(request, status: 200, body: #"{"missing_media":[]}"#)
            }
            let count = getCount.withValue {
                $0 += 1
                return $0
            }
            let hash = count == 1 ? "null" : #""\#(expectedHash)""#
            return Self.response(
                request,
                status: 200,
                body: #"{"entry":{"client_content_hash":\#(hash),"media":[{"asset_key":"\#(key)"}]}}"#
            )
        }

        _ = try await Publisher(context: container.mainContext).publish(entry, with: api)

        let cache = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<EntryMetadataCache>()).first)
        XCTAssertEqual(cache.confirmedMedia, [assetID: key])
        XCTAssertEqual(entry.publishStatus, .published)
    }

    func testUnavailableLegacyPhotoDoesNotShrinkWhenRemoteCannotBeChecked() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        entry.mediaAssetIDs = ["unavailable-photo-\(UUID().uuidString)"]
        entry.publishStatus = .published
        entry.publishedAt = .now
        let api = makeAPI()
        let destination = PublishDestination(baseURL: api.destinationURL, keyFingerprint: api.keyFingerprint)
        container.mainContext.insert(destination)
        entry.publishDestinationID = destination.id
        try container.mainContext.save()
        let putEntryCalled = LockedValue(false)
        TestURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                putEntryCalled.withValue { $0 = true }
            }
            return Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }

        do {
            _ = try await Publisher(context: container.mainContext).publish(entry, with: api)
            XCTFail("Expected the missing remote state to block replacement")
        } catch let error as PublishingError {
            guard case .remoteEntryNotFound = error else {
                return XCTFail("Unexpected publishing error: \(error)")
            }
        }

        XCTAssertFalse(putEntryCalled.withValue { $0 })
        XCTAssertEqual(entry.publishStatus, .needsUpdate)
        XCTAssertEqual(entry.mediaAssetIDs.count, 1)
    }

    func testLegacyBindingRequiresAuthenticatedExistingEntry() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        entry.publishStatus = .published
        let api = makeAPI()
        TestURLProtocol.handler = { request in
            Self.response(request, status: 200, body: #"{"entry":{"client_content_hash":null,"media":[]}}"#)
        }

        await Publisher(context: container.mainContext).bindLegacyEntries(to: api)

        XCTAssertNotNil(entry.publishDestinationID)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).count, 1)
    }

    func testLegacyBindingKeepsMissingEntryUnboundAndPublished() async throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        entry.publishStatus = .published
        TestURLProtocol.handler = { request in
            Self.response(request, status: 404, body: #"{"error":{"code":"UNKNOWN_ENTRY","message":"Missing"}}"#)
        }

        await Publisher(context: container.mainContext).bindLegacyEntries(to: makeAPI())

        XCTAssertNil(entry.publishDestinationID)
        XCTAssertEqual(entry.publishStatus, .published)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PublishDestination>()).isEmpty)
    }

    func testRetryDateUsesEarliestDueAndClampsPastToNow() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            Publisher.nextRetryDate([now.addingTimeInterval(30), now.addingTimeInterval(10)], after: now),
            now.addingTimeInterval(10)
        )
        XCTAssertEqual(Publisher.nextRetryDate([now.addingTimeInterval(-1)], after: now), now)
        XCTAssertNil(Publisher.nextRetryDate([], after: now))
    }

    func testJournalRenameQueuesDestinationBoundEntries() throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let destination = PublishDestination(baseURL: "https://journal.example", keyFingerprint: "digest")
        container.mainContext.insert(destination)
        entry.publishDestinationID = destination.id
        entry.publishStatus = .published
        try container.mainContext.save()

        entry.journal?.name = "Renamed journal"
        try Publisher(context: container.mainContext).propagateJournalRename(try XCTUnwrap(entry.journal))

        let operation = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PublishOperation>()).first)
        XCTAssertEqual(entry.publishStatus, .needsUpdate)
        XCTAssertEqual(operation.entryID, entry.id)
        XCTAssertEqual(operation.kind, .publish)
    }

    func testTagRenameCoalescesExistingPublishOperation() throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let destination = PublishDestination(baseURL: "https://journal.example", keyFingerprint: "digest")
        let tag = Tag(name: "Old", color: .blue)
        entry.tags = [tag]
        entry.publishDestinationID = destination.id
        entry.publishStatus = .published
        let operation = PublishOperation(
            entryID: entry.id,
            destinationID: destination.id,
            kind: .publish,
            requestedEntryUpdate: .distantPast
        )
        container.mainContext.insert(destination)
        container.mainContext.insert(tag)
        container.mainContext.insert(operation)
        try container.mainContext.save()

        tag.name = "New"
        try Publisher(context: container.mainContext).propagateTagUpdate(tag)

        let operations = try container.mainContext.fetch(FetchDescriptor<PublishOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(entry.publishStatus, .needsUpdate)
        XCTAssertEqual(operations[0].requestedEntryUpdate, entry.updatedAt)
    }

    func testTagColorEditQueuesPublishedEntryUpdate() throws {
        let container = try makeContainer()
        let entry = try makeEntry(in: container.mainContext)
        let destination = PublishDestination(baseURL: "https://journal.example", keyFingerprint: "digest")
        let tag = Tag(name: "Friends", color: .blue)
        entry.tags = [tag]
        entry.publishDestinationID = destination.id
        entry.publishStatus = .published
        container.mainContext.insert(destination)
        container.mainContext.insert(tag)
        try container.mainContext.save()

        tag.color = .green
        try Publisher(context: container.mainContext).propagateTagUpdate(tag)

        XCTAssertEqual(entry.publishStatus, .needsUpdate)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PublishOperation>()).count, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: JourneySchemaV7.self),
            migrationPlan: JourneyMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    private func makeEntry(in context: ModelContext) throws -> Entry {
        let journal = Journal(name: "Test")
        let entry = Entry()
        entry.title = "Durable publish"
        entry.localDay = "2026-09-17"
        entry.journal = journal
        context.insert(journal)
        context.insert(entry)
        try context.save()
        return entry
    }

    private func makeAPI() -> JourneyAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return JourneyAPI(
            baseURL: URL(string: "https://journal.example")!,
            key: String(repeating: "k", count: 32),
            session: URLSession(configuration: configuration)
        )
    }

    nonisolated private static func response(_ request: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }

}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
