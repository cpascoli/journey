import Foundation
import SwiftData

/// A website/key pair. The key itself remains in Keychain; only its digest is modeled.
@Model
final class PublishDestination {
    var id: UUID = UUID()
    var baseURL: String = ""
    var keyFingerprint: String = ""
    var createdAt: Date = Date.now

    init(baseURL: String, keyFingerprint: String) {
        self.baseURL = baseURL
        self.keyFingerprint = keyFingerprint
    }
}

@Model
final class PublishOperation {
    var id: UUID = UUID()
    var entryID: UUID = UUID()
    var destinationID: UUID = UUID()
    var kindRaw: String = PublishOperationKind.publish.rawValue
    var requestedEntryUpdate: Date = Date.distantPast
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var attemptCount: Int = 0
    var nextAttemptAt: Date = Date.distantPast
    /// Safe for display: never contains request headers, bodies, URLs with secrets, or keys.
    var lastError: String = ""

    init(entryID: UUID, destinationID: UUID, kind: PublishOperationKind, requestedEntryUpdate: Date) {
        self.entryID = entryID
        self.destinationID = destinationID
        kindRaw = kind.rawValue
        self.requestedEntryUpdate = requestedEntryUpdate
    }

    var kind: PublishOperationKind {
        get { PublishOperationKind(rawValue: kindRaw) ?? .publish }
        set { kindRaw = newValue.rawValue }
    }
}

nonisolated enum PublishOperationKind: String, Codable, Sendable {
    case publish
    case unpublish
}
