import Foundation
import SwiftData

@Model
final class Entry {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var date: Date = Date.now
    // The civil day and timezone where this entry occurred. These do not change
    // when the device later travels to another timezone.
    var localDay: String = ""
    var timeZoneIdentifier: String = ""
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
    /// The immutable publishing destination while this entry exists online or has queued work.
    var publishDestinationID: UUID?
    var sharedLocationPrecisionRaw: String = LocationPrecision.city.rawValue
    // Who can read the entry on the website once it's published. Only you until you choose otherwise.
    var visibilityRaw: String = EntryVisibility.onlyMe.rawValue

    var journal: Journal?
    @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []
    @Relationship(inverse: \Tag.entries) var tags: [Tag]? = []

    init() {}

    var publishStatus: PublishStatus {
        get { PublishStatus(rawValue: publishStatusRaw) ?? .notPublished }
        set { publishStatusRaw = newValue.rawValue }
    }

    var sharedLocationPrecision: LocationPrecision {
        get { LocationPrecision(rawValue: sharedLocationPrecisionRaw) ?? .city }
        set { sharedLocationPrecisionRaw = newValue.rawValue }
    }

    var visibility: EntryVisibility {
        get { EntryVisibility(rawValue: visibilityRaw) ?? .onlyMe }
        set { visibilityRaw = newValue.rawValue }
    }

    var narrativeSource: NarrativeSource {
        get { NarrativeSource(rawValue: narrativeSourceRaw) ?? .user }
        set { narrativeSourceRaw = newValue.rawValue }
    }

    var isPublicationBound: Bool {
        publishDestinationID != nil || publishStatus != .notPublished
    }
}

nonisolated enum NarrativeSource: String, Codable, Sendable {
    case onDevice, chatGPT, user
}

nonisolated enum PublishStatus: String, Codable, Sendable {
    case notPublished, published, needsUpdate
}

/// Raw values are the website's `visibility` values.
nonisolated enum EntryVisibility: String, Codable, CaseIterable, Sendable {
    /// Only you (and the agents your keys allow).
    case onlyMe = "private"
    /// People you invite, if their invite includes all of the entry's tags.
    case invites = "shared"
}

nonisolated enum LocationPrecision: String, Codable, CaseIterable, Sendable {
    case exact, neighborhood, city, hidden
}
