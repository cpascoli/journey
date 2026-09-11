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
}

nonisolated enum PublishStatus: String, Codable, Sendable {
    case notPublished, published, needsUpdate
}

nonisolated enum LocationPrecision: String, Codable, CaseIterable, Sendable {
    case exact, neighborhood, city, hidden
}
