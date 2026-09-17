import Foundation
import Observation
import Photos
import SwiftData

/// Publishes entries to the website through the owner API: the entry's tags
/// first (entries refer to them by id, and they're the sharing rules), then the
/// entry, then whichever of its photos the website doesn't have yet.
@Observable
final class Publisher {
    enum Step: Equatable {
        case idle, tags, entry
        case photo(Int, of: Int)
        case removing
    }

    struct Report {
        var failedPhotos = 0
        var skippedVideos = 0
        /// Photos no longer in the library, or outside a limited selection.
        var unavailable = 0
    }

    private(set) var step = Step.idle
    var isWorking: Bool { step != .idle }

    /// The entry's media as the website will get it: photos in the entry's order.
    /// The website only takes photos, so videos stay on the phone for now.
    static func media(of entry: Entry) -> (photos: [PHAsset], videos: Int, unavailable: Int) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: entry.mediaAssetIDs, options: nil)
        let found = result.objects(at: IndexSet(integersIn: 0..<result.count))
        let byID = Dictionary(found.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let assets = entry.mediaAssetIDs.compactMap { byID[$0] }
        return (
            assets.filter { $0.mediaType == .image },
            assets.filter { $0.mediaType == .video }.count,
            entry.mediaAssetIDs.count - assets.count
        )
    }

    /// Saves the entry on the website with its current visibility and location precision.
    /// Safe to repeat: only photos the website is missing are uploaded.
    func publish(_ entry: Entry, with api: JourneyAPI) async throws -> Report {
        defer { step = .idle }
        let editedAt = entry.updatedAt

        step = .tags
        for tag in entry.sortedTags {
            try await api.putTag(id: tag.id, name: tag.name, color: tag.colorName)
        }

        step = .entry
        let media = Self.media(of: entry)
        var report = Report(skippedVideos: media.videos, unavailable: media.unavailable)
        let keys = media.photos.map { PhotoExport.key(for: $0.localIdentifier) }
        let payload = await Self.payload(for: entry, mediaKeys: keys)
        let missing = Set(try await api.putEntry(id: entry.id, payload))
        // The entry is on the website from here on, even if a photo fails below.
        entry.remoteID = entry.id.uuidString.lowercased()
        entry.publishedAt = .now
        entry.publishStatus = .needsUpdate

        let uploads = media.photos.indices.filter { missing.contains(keys[$0]) }
        for (done, index) in uploads.enumerated() {
            step = .photo(done + 1, of: uploads.count)
            let asset = media.photos[index]
            guard let photo = await PhotoExport.photo(for: asset) else {
                report.failedPhotos += 1
                continue
            }
            try await api.putPhoto(entryID: entry.id, key: keys[index], photo, takenAt: asset.creationDate, sortOrder: index)
        }

        // An edit made while this ran isn't on the website yet.
        entry.publishStatus = report.failedPhotos == 0 && entry.updatedAt == editedAt ? .published : .needsUpdate
        try? entry.modelContext?.save()
        return report
    }

    /// Removes the entry and its photos from the website. The entry stays on the phone.
    func unpublish(_ entry: Entry, with api: JourneyAPI) async throws {
        step = .removing
        defer { step = .idle }
        try await api.deleteEntry(id: entry.id)
        entry.publishStatus = .notPublished
        entry.remoteID = nil
        entry.publishedAt = nil
        try? entry.modelContext?.save()
    }

    private static func payload(for entry: Entry, mediaKeys: [String]) async -> EntryPayload {
        let precision = entry.sharedLocationPrecision
        var location: EntryPayload.Location?
        // Hidden means nothing is sent, not just nothing shown. Otherwise the website
        // reduces the location to the precision before storing it.
        if precision != .hidden, entry.placeName != nil || entry.latitude != nil {
            var locality: String?
            if let latitude = entry.latitude, let longitude = entry.longitude {
                locality = await PlaceNamer.locality(latitude: latitude, longitude: longitude)
            }
            location = EntryPayload.Location(
                placeName: entry.placeName, locality: locality, latitude: entry.latitude, longitude: entry.longitude
            )
        }
        let translation = entry.translationLanguage.isEmpty ? nil : EntryPayload.Translation(
            language: entry.translationLanguage,
            title: entry.translatedTitle,
            notes: entry.translatedBody,
            narrative: entry.translatedNarrative
        )
        return EntryPayload(
            journalName: entry.journal?.name ?? "Main",
            occurredAt: entry.date.ISO8601Format(),
            day: dayString(entry.date),
            title: entry.title,
            notes: entry.body,
            narrative: entry.narrative,
            narrativeSource: entry.narrativeSource.apiValue,
            location: location,
            locationPrecision: precision.rawValue,
            translation: translation,
            visibility: entry.visibility.rawValue,
            tagIds: entry.sortedTags.map { $0.id.uuidString.lowercased() },
            mediaKeys: mediaKeys
        )
    }

    /// The calendar day as the writer saw it, e.g. "2026-09-11".
    private static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

private extension NarrativeSource {
    var apiValue: String {
        switch self {
        case .onDevice: "on_device"
        case .chatGPT: "chatgpt"
        case .user: "user"
        }
    }
}
