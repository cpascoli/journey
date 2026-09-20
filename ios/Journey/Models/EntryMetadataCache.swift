import Foundation
import SwiftData

/// Durable, derived state that can be rebuilt without changing the entry model.
/// Keeping it separate preserves the checksums of the already-shipped schemas.
@Model
final class EntryMetadataCache {
    var id: UUID = UUID()
    var entryID: UUID = UUID()
    var locality: String?
    var timeZoneIdentifier: String = ""
    var geocodedLatitude: Double?
    var geocodedLongitude: Double?
    /// Parallel arrays containing the last media set confirmed by the website.
    var confirmedPhotoAssetIDs: [String] = []
    var confirmedMediaKeys: [String] = []

    init(entryID: UUID) {
        self.entryID = entryID
    }

    static func findOrCreate(for entryID: UUID, in context: ModelContext) throws -> EntryMetadataCache {
        let descriptor = FetchDescriptor<EntryMetadataCache>(predicate: #Predicate { $0.entryID == entryID })
        if let cache = try context.fetch(descriptor).first {
            return cache
        }
        let cache = EntryMetadataCache(entryID: entryID)
        context.insert(cache)
        return cache
    }

    var hasCurrentCoordinates: Bool {
        geocodedLatitude != nil && geocodedLongitude != nil
    }

    func matches(latitude: Double, longitude: Double) -> Bool {
        geocodedLatitude == latitude && geocodedLongitude == longitude
    }

    var confirmedMedia: [String: String] {
        var media: [String: String] = [:]
        for (assetID, key) in zip(confirmedPhotoAssetIDs, confirmedMediaKeys) {
            media[assetID] = key
        }
        return media
    }
}
