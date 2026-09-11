import Foundation
import SwiftData

@Model
final class Entry {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var date: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    // Photos library identifiers; the media itself stays in the user's library.
    var mediaAssetIDs: [String] = []
    var isAIGenerated: Bool = false
    // The story around the entry, drafted by AI or written by the user. Kept apart
    // from `body`, which is the user's own notes and is never touched by AI.
    var narrative: String = ""
    var narrativeSourceRaw: String = NarrativeSource.user.rawValue
    // On-device translation into `translationLanguage` ("en", "it"); originals stay untouched.
    var translationLanguage: String = ""
    var translatedTitle: String = ""
    var translatedBody: String = ""
    var translatedNarrative: String = ""

    var publishStatusRaw: String = PublishStatus.notPublished.rawValue
    var remoteID: String?
    var publishedAt: Date?
    var sharedLocationPrecisionRaw: String = LocationPrecision.city.rawValue

    var journal: Journal?
    @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []

    init() {}

    var publishStatus: PublishStatus {
        get { PublishStatus(rawValue: publishStatusRaw) ?? .notPublished }
        set { publishStatusRaw = newValue.rawValue }
    }

    var sharedLocationPrecision: LocationPrecision {
        get { LocationPrecision(rawValue: sharedLocationPrecisionRaw) ?? .city }
        set { sharedLocationPrecisionRaw = newValue.rawValue }
    }

    var narrativeSource: NarrativeSource {
        get { NarrativeSource(rawValue: narrativeSourceRaw) ?? .user }
        set { narrativeSourceRaw = newValue.rawValue }
    }
}

nonisolated enum NarrativeSource: String, Codable, Sendable {
    case onDevice, chatGPT, user
}

nonisolated enum PublishStatus: String, Codable, Sendable {
    case notPublished, published, needsUpdate
}

nonisolated enum LocationPrecision: String, Codable, CaseIterable, Sendable {
    case exact, neighborhood, city, hidden
}
