import Foundation
import Observation
import Photos
import SwiftData

/// Publishes entries to the website through the owner API: the entry's tags
/// first (entries refer to them by id, and they're the sharing rules), then the
/// entry, then whichever of its photos and videos the website doesn't have yet.
@Observable
final class Publisher {
    enum MediaAvailability: Equatable {
        case photo(key: String)
        case video(key: String)
        /// Known, but deliberately not sent (a video too long or too large to
        /// export). Unlike `.unavailable` this must not fall back to a
        /// previously confirmed key: the item is being left off on purpose.
        case skipped
        case unavailable
    }

    enum Step: Equatable {
        case idle, tags, entry
        case exporting(Int, of: Int)
        case media(Int, of: Int)
        case removing
    }

    struct Report {
        var failedPhotos = 0
        var failedVideos = 0
        /// Videos too long, or too large once exported, to send.
        var skippedVideos = 0
        /// Photos and videos no longer in the library, or outside a limited selection.
        var unavailable = 0
    }

    private(set) var step = Step.idle
    var isWorking: Bool { step != .idle }
    private let context: ModelContext
    private var processingIDs: Set<UUID> = []
    private var retryTask: Task<Void, Never>?
    private var isActive = false

    init(context: ModelContext) {
        self.context = context
    }

    /// The entry's media as the website will get it, in the entry's order.
    static func media(of entry: Entry) -> (photos: [PHAsset], videos: [PHAsset], unavailable: Int) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: entry.mediaAssetIDs, options: nil)
        let found = result.objects(at: IndexSet(integersIn: 0..<result.count))
        let byID = Dictionary(found.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let assets = entry.mediaAssetIDs.compactMap { byID[$0] }
        return (
            assets.filter { $0.mediaType == .image },
            assets.filter { $0.mediaType == .video },
            entry.mediaAssetIDs.count - assets.count
        )
    }

    /// Resolves the ordered server media set without confusing temporary
    /// unavailability with intentional removal. An item the app has decided to
    /// skip always wins over stale confirmation that used the same Photos ID.
    static func resolvedMedia(
        currentAssetIDs: [String],
        availability: [String: MediaAvailability],
        confirmed: [String: String]
    ) -> [(assetID: String, key: String)] {
        currentAssetIDs.compactMap { assetID in
            switch availability[assetID] ?? .unavailable {
            case let .photo(key):
                (assetID, key)
            case let .video(key):
                (assetID, key)
            case .skipped:
                nil
            case .unavailable:
                confirmed[assetID].map { (assetID, $0) }
            }
        }
    }

    /// Repoints published work at the same website under a new address.
    ///
    /// A destination is identified by its URL and key fingerprint, so renaming
    /// the site would otherwise orphan every published entry — and the only
    /// alternative, unpublishing them all, deletes their photos and readers'
    /// comments. This proves the new address serves the same database before
    /// rebinding: it reads a bound entry back and requires the content hash to
    /// match. Nothing on the website changes; only where the app looks for it.
    func moveDestination(to api: JourneyAPI) async throws {
        let bound = try context.fetch(FetchDescriptor<Entry>()).filter {
            $0.publishDestinationID != nil
        }
        guard let sample = bound.first, let destinationID = sample.publishDestinationID else {
            throw PublishingError.nothingToMove
        }
        let descriptor = FetchDescriptor<PublishDestination>(
            predicate: #Predicate { $0.id == destinationID }
        )
        guard let destination = try context.fetch(descriptor).first else {
            throw PublishingError.nothingToMove
        }
        guard destination.keyFingerprint == api.keyFingerprint else {
            throw PublishingError.differentDestination
        }
        guard destination.baseURL != api.destinationURL else { return }

        // The proof: the same entry, with the same content, at the new address.
        let cache = try? metadataCache(for: sample.id)
        let expected = try await Self.payload(
            for: sample,
            mediaKeys: (cache?.confirmedMediaKeys ?? []),
            locationCache: cache
        ).addingContentHash().clientContentHash
        guard let remote = try await api.entryState(id: sample.id) else {
            throw PublishingError.notTheSameWebsite
        }
        guard expected == nil || remote.clientContentHash == expected else {
            throw PublishingError.notTheSameWebsite
        }

        destination.baseURL = api.destinationURL
        try context.save()
    }

    /// Commits destination binding and publish intent before the first request.
    func publish(_ entry: Entry, with api: JourneyAPI) async throws -> Report {
        try await ensureLegacyBinding(entry, to: api)
        let operation = try enqueue(entry, kind: .publish, api: api)
        return try await process(operation, api: api)
    }

    /// Commits an unpublish tombstone before the first request.
    func unpublish(_ entry: Entry, with api: JourneyAPI) async throws {
        try await ensureLegacyBinding(entry, to: api)
        let operation = try enqueue(entry, kind: .unpublish, api: api)
        _ = try await process(operation, api: api)
    }

    /// Starts lifecycle recovery and keeps retrying while the app remains active.
    func activate() async {
        isActive = true
        await processPending()
    }

    func deactivate() {
        isActive = false
        retryTask?.cancel()
        retryTask = nil
    }

    /// Retries durable work after launch or whenever the app returns to the foreground.
    func processPending() async {
        if let configured = JourneyAPI.configured() {
            await bindLegacyEntries(to: configured)
        }
        let now = Date.now
        let descriptor = FetchDescriptor<PublishOperation>(
            predicate: #Predicate { $0.nextAttemptAt <= now },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let operations = try? context.fetch(descriptor) else { return }
        for operation in operations {
            guard let api = api(for: operation.destinationID) else { continue }
            _ = try? await process(operation, api: api)
        }
        scheduleRetry()
    }

    /// Explicit API injection keeps retry behavior deterministic in service tests.
    func processPending(with api: JourneyAPI) async {
        let now = Date.now
        let descriptor = FetchDescriptor<PublishOperation>(
            predicate: #Predicate { $0.nextAttemptAt <= now },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let operations = try? context.fetch(descriptor) else { return }
        for operation in operations {
            let destinationID = operation.destinationID
            let destination = try? context.fetch(
                FetchDescriptor<PublishDestination>(predicate: #Predicate { $0.id == destinationID })
            ).first
            guard destination?.baseURL == api.destinationURL,
                  destination?.keyFingerprint == api.keyFingerprint else { continue }
            _ = try? await process(operation, api: api)
        }
    }

    /// Marks destination-bound entries after shared metadata changes. Existing
    /// publish work is coalesced; an unpublish tombstone is never reversed.
    func propagateJournalRename(_ journal: Journal) throws {
        try queueRenameUpdates(for: journal.entries ?? [])
    }

    func propagateTagUpdate(_ tag: Tag) throws {
        try queueRenameUpdates(for: tag.entries ?? [])
    }

    static func payload(
        for entry: Entry,
        mediaKeys: [String],
        locationCache: EntryMetadataCache? = nil
    ) async -> EntryPayload {
        let precision = entry.sharedLocationPrecision
        var location: EntryPayload.Location?
        // Hidden means nothing is sent, not just nothing shown. Otherwise the website
        // reduces the location to the precision before storing it.
        if precision != .hidden, entry.placeName != nil || entry.latitude != nil {
            let locality: String? = if let latitude = entry.latitude, let longitude = entry.longitude,
                                       let locationCache,
                                       locationCache.matches(latitude: latitude, longitude: longitude) {
                locationCache.locality
            } else {
                nil
            }
            location = EntryPayload.Location(
                placeName: entry.placeName,
                locality: locality,
                latitude: entry.latitude,
                longitude: entry.longitude
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
            day: entry.localDay,
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

    /// Rebuilds V7's derived cache from server media without guessing from
    /// Photos availability. Keys absent from the current entry stay removed.
    static func recoveredConfirmedMedia(
        currentAssetIDs: [String],
        remoteMediaKeys: [String]
    ) -> [String: String] {
        let remote = Set(remoteMediaKeys)
        return Dictionary(uniqueKeysWithValues: currentAssetIDs.compactMap { assetID in
            let key = MediaKey.key(for: assetID)
            return remote.contains(key) ? (assetID, key) : nil
        })
    }

    static func nextRetryDate(_ dates: [Date], after now: Date) -> Date? {
        dates.min().map { max($0, now) }
    }

    private func enqueue(_ entry: Entry, kind: PublishOperationKind, api: JourneyAPI) throws -> PublishOperation {
        if let bound = entry.publishDestinationID {
            let descriptor = FetchDescriptor<PublishDestination>(predicate: #Predicate { $0.id == bound })
            guard let destination = try context.fetch(descriptor).first,
                  destination.baseURL == api.destinationURL,
                  destination.keyFingerprint == api.keyFingerprint else {
                throw PublishingError.differentDestination
            }
        }
        let destination = try destination(for: api)
        entry.publishDestinationID = destination.id
        if kind == .publish {
            entry.publishStatus = .needsUpdate
        }

        let entryID = entry.id
        let destinationID = destination.id
        let descriptor = FetchDescriptor<PublishOperation>(
            predicate: #Predicate { $0.entryID == entryID && $0.destinationID == destinationID }
        )
        let operation: PublishOperation
        if let existing = try context.fetch(descriptor).first {
            operation = existing
            operation.kind = kind
            operation.requestedEntryUpdate = entry.updatedAt
            operation.updatedAt = .now
            operation.nextAttemptAt = .distantPast
            operation.lastError = ""
        } else {
            operation = PublishOperation(
                entryID: entry.id,
                destinationID: destination.id,
                kind: kind,
                requestedEntryUpdate: entry.updatedAt
            )
            context.insert(operation)
        }
        try context.save()
        return operation
    }

    private func destination(for api: JourneyAPI) throws -> PublishDestination {
        let url = api.destinationURL
        let fingerprint = api.keyFingerprint
        let descriptor = FetchDescriptor<PublishDestination>(
            predicate: #Predicate { $0.baseURL == url && $0.keyFingerprint == fingerprint }
        )
        if let destination = try context.fetch(descriptor).first {
            return destination
        }
        let destination = PublishDestination(baseURL: url, keyFingerprint: fingerprint)
        context.insert(destination)
        return destination
    }

    private func queueRenameUpdates(for entries: [Entry]) throws {
        let changedAt = Date.now
        for entry in entries where entry.isPublicationBound {
            guard let destinationID = entry.publishDestinationID else {
                entry.publishStatus = .needsUpdate
                entry.updatedAt = changedAt
                continue
            }
            let entryID = entry.id
            let descriptor = FetchDescriptor<PublishOperation>(
                predicate: #Predicate { $0.entryID == entryID && $0.destinationID == destinationID }
            )
            if let operation = try context.fetch(descriptor).first {
                guard operation.kind != .unpublish else { continue }
                entry.publishStatus = .needsUpdate
                entry.updatedAt = changedAt
                operation.requestedEntryUpdate = changedAt
                operation.updatedAt = changedAt
                operation.nextAttemptAt = .distantPast
                operation.lastError = ""
            } else {
                entry.publishStatus = .needsUpdate
                entry.updatedAt = changedAt
                context.insert(PublishOperation(
                    entryID: entryID,
                    destinationID: destinationID,
                    kind: .publish,
                    requestedEntryUpdate: changedAt
                ))
            }
        }
        try context.save()
    }

    /// V5 knew an entry was online but did not persist its destination. Bind it
    /// only after this exact website and key authenticate and prove the entry exists.
    func bindLegacyEntries(to api: JourneyAPI) async {
        let notPublished = PublishStatus.notPublished.rawValue
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.publishStatusRaw != notPublished && $0.publishDestinationID == nil }
        )
        guard let entries = try? context.fetch(descriptor) else { return }
        guard !entries.isEmpty else { return }
        for entry in entries {
            do {
                try await ensureLegacyBinding(entry, to: api)
            } catch {
                continue
            }
        }
    }

    private func ensureLegacyBinding(_ entry: Entry, to api: JourneyAPI) async throws {
        guard entry.publishDestinationID == nil, entry.publishStatus != .notPublished else { return }
        guard try await api.entryState(id: entry.id) != nil else {
            throw PublishingError.remoteEntryNotFound
        }
        let destination = try destination(for: api)
        entry.publishDestinationID = destination.id
        try context.save()
    }

    private func api(for destinationID: UUID) -> JourneyAPI? {
        let descriptor = FetchDescriptor<PublishDestination>(predicate: #Predicate { $0.id == destinationID })
        guard let destination = try? context.fetch(descriptor).first,
              let api = JourneyAPI.configured(),
              api.destinationURL == destination.baseURL,
              api.keyFingerprint == destination.keyFingerprint else { return nil }
        return api
    }

    private func process(_ operation: PublishOperation, api: JourneyAPI) async throws -> Report {
        guard !processingIDs.contains(operation.id) else { return Report() }
        processingIDs.insert(operation.id)
        defer {
            processingIDs.remove(operation.id)
            step = .idle
        }
        operation.attemptCount += 1
        operation.updatedAt = .now
        try context.save()

        do {
            switch operation.kind {
            case .publish:
                return try await processPublish(operation, api: api)
            case .unpublish:
                try await processUnpublish(operation, api: api)
                return Report()
            }
        } catch {
            let reconciled: Bool
            switch operation.kind {
            case .publish:
                reconciled = await reconcilePublish(operation, api: api)
            case .unpublish:
                reconciled = await reconcileUnpublish(operation, api: api)
            }
            if reconciled { return Report() }
            operation.lastError = error.localizedDescription
            operation.nextAttemptAt = Date.now.addingTimeInterval(retryDelay(attempt: operation.attemptCount))
            operation.updatedAt = .now
            try context.save()
            scheduleRetry()
            throw error
        }
    }

    private func processPublish(_ operation: PublishOperation, api: JourneyAPI) async throws -> Report {
        guard let entry = try entry(id: operation.entryID) else {
            operation.kind = .unpublish
            try context.save()
            try await processUnpublish(operation, api: api)
            return Report()
        }
        let targetUpdate = operation.requestedEntryUpdate
        step = .tags
        for tag in entry.sortedTags {
            try await api.putTag(id: tag.id, name: tag.name, color: tag.colorName)
        }

        let cache = try metadataCache(for: entry.id)
        await PlaceNamer.refresh(entry: entry, cache: cache)
        try context.save()
        let media = Self.media(of: entry)
        var report = Report(unavailable: media.unavailable)
        let assetsByID = Dictionary(
            uniqueKeysWithValues: (media.photos + media.videos).map { ($0.localIdentifier, $0) }
        )
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: entry.mediaAssetIDs, options: nil)
        let found = fetched.objects(at: IndexSet(integersIn: 0..<fetched.count))
        var availability: [String: MediaAvailability] = [:]
        for asset in found where asset.mediaType == .image {
            availability[asset.localIdentifier] = .photo(key: MediaKey.key(for: asset.localIdentifier))
        }
        for asset in found where asset.mediaType != .image && asset.mediaType != .video {
            availability[asset.localIdentifier] = .unavailable
        }

        // Videos are exported before the media set is decided, not during the
        // upload loop: a clip that turns out too large has to be left out of
        // `media_keys` altogether, and by upload time that list is already
        // committed. Only unconfirmed videos are exported, so re-publishing an
        // entry whose videos the website already has re-encodes nothing.
        let confirmedBeforeExport = cache.confirmedMedia
        var exported: [String: VideoExport.Video] = [:]
        defer { for video in exported.values { VideoExport.discard(video) } }
        let videos = media.videos
        for (index, asset) in videos.enumerated() {
            let assetID = asset.localIdentifier
            let key = MediaKey.key(for: assetID)
            if confirmedBeforeExport[assetID] == key {
                availability[assetID] = .video(key: key)
                continue
            }
            step = .exporting(index + 1, of: videos.count)
            switch await VideoExport.video(for: asset) {
            case let .success(video):
                exported[assetID] = video
                availability[assetID] = .video(key: key)
            case .failure:
                report.skippedVideos += 1
                availability[assetID] = .skipped
            }
        }
        var confirmed = cache.confirmedMedia
        let hasUnconfirmedUnavailableMedia = entry.mediaAssetIDs.contains { assetID in
            availability[assetID] == nil && confirmed[assetID] == nil
        }
        let wasPreviouslyOnline = entry.remoteID != nil || entry.publishedAt != nil
        if wasPreviouslyOnline, hasUnconfirmedUnavailableMedia {
            guard let remote = try await api.entryState(id: entry.id) else {
                throw PublishingError.remoteEntryNotFound
            }
            confirmed.merge(
                Self.recoveredConfirmedMedia(
                    currentAssetIDs: entry.mediaAssetIDs,
                    remoteMediaKeys: remote.mediaKeys
                ),
                uniquingKeysWith: { cached, _ in cached }
            )
            cache.confirmedPhotoAssetIDs = entry.mediaAssetIDs.filter { confirmed[$0] != nil }
            cache.confirmedMediaKeys = cache.confirmedPhotoAssetIDs.compactMap { confirmed[$0] }
            try context.save()
        }
        let resolved = Self.resolvedMedia(
            currentAssetIDs: entry.mediaAssetIDs,
            availability: availability,
            confirmed: confirmed
        )
        let keys = resolved.map(\.key)
        step = .entry
        let payload = try await Self.payload(
            for: entry,
            mediaKeys: keys,
            locationCache: cache
        ).addingContentHash()
        let missing = Set(try await api.putEntry(
            id: entry.id,
            payload
        ))
        entry.remoteID = entry.id.uuidString.lowercased()
        entry.publishedAt = entry.publishedAt ?? .now
        entry.publishStatus = .needsUpdate
        try context.save()

        let uploads = resolved.enumerated().compactMap { index, item in
            assetsByID[item.assetID].map { (index, item.key, $0) }
        }.filter { missing.contains($0.1) }
        for (done, upload) in uploads.enumerated() {
            step = .media(done + 1, of: uploads.count)
            let (index, key, asset) = upload
            if asset.mediaType == .video {
                // Exported above; absent only if the website asked for a key
                // the app decided to skip, which resolvedMedia already excludes.
                guard let video = exported[asset.localIdentifier] else {
                    report.failedVideos += 1
                    continue
                }
                try await api.putVideo(
                    entryID: entry.id,
                    key: key,
                    video,
                    takenAt: asset.creationDate,
                    sortOrder: index
                )
                continue
            }
            guard let photo = await PhotoExport.photo(for: asset) else {
                report.failedPhotos += 1
                continue
            }
            try await api.putPhoto(
                entryID: entry.id,
                key: key,
                photo,
                takenAt: asset.creationDate,
                sortOrder: index
            )
        }
        guard report.failedPhotos == 0, report.failedVideos == 0,
              let state = try await api.entryState(id: entry.id),
              state.mediaKeys == keys,
              state.clientContentHash == payload.clientContentHash else {
            throw PublishingError.photosNotConfirmed
        }
        cache.confirmedPhotoAssetIDs = resolved.map(\.assetID)
        cache.confirmedMediaKeys = keys
        try finishPublish(operation, entry: entry, targetUpdate: targetUpdate)
        return report
    }

    private func processUnpublish(_ operation: PublishOperation, api: JourneyAPI) async throws {
        step = .removing
        if try await api.entryState(id: operation.entryID) != nil {
            try await api.deleteEntry(id: operation.entryID)
        }
        guard try await api.entryState(id: operation.entryID) == nil else {
            throw PublishingError.removalNotConfirmed
        }
        try finishUnpublish(operation)
    }

    private func reconcilePublish(_ operation: PublishOperation, api: JourneyAPI) async -> Bool {
        guard let entry = try? entry(id: operation.entryID) else { return false }
        guard let cache = try? metadataCache(for: entry.id) else { return false }
        let media = Self.media(of: entry)
        var availability: [String: MediaAvailability] = [:]
        for asset in media.photos {
            availability[asset.localIdentifier] = .photo(key: MediaKey.key(for: asset.localIdentifier))
        }
        // Reconciliation must stay cheap, so no video is exported here: one
        // counts only if the website already confirmed it. An unconfirmed
        // video leaves the set unmatched, which simply means a retry.
        let confirmed = cache.confirmedMedia
        for asset in media.videos {
            let assetID = asset.localIdentifier
            let key = MediaKey.key(for: assetID)
            if confirmed[assetID] == key {
                availability[assetID] = .video(key: key)
            }
        }
        let resolved = Self.resolvedMedia(
            currentAssetIDs: entry.mediaAssetIDs,
            availability: availability,
            confirmed: confirmed
        )
        let keys = resolved.map(\.key)
        let basePayload = await Self.payload(for: entry, mediaKeys: keys, locationCache: cache)
        guard let payload = try? basePayload.addingContentHash(),
              let state = try? await api.entryState(id: entry.id),
              state.mediaKeys == keys,
              state.clientContentHash == payload.clientContentHash else { return false }
        do {
            cache.confirmedPhotoAssetIDs = resolved.map(\.assetID)
            cache.confirmedMediaKeys = keys
            try finishPublish(operation, entry: entry, targetUpdate: operation.requestedEntryUpdate)
            return true
        } catch {
            return false
        }
    }

    private func reconcileUnpublish(_ operation: PublishOperation, api: JourneyAPI) async -> Bool {
        do {
            guard try await api.entryState(id: operation.entryID) == nil else { return false }
            try finishUnpublish(operation)
            return true
        } catch {
            return false
        }
    }

    private func finishPublish(_ operation: PublishOperation, entry: Entry, targetUpdate: Date) throws {
        entry.remoteID = entry.id.uuidString.lowercased()
        entry.publishedAt = entry.publishedAt ?? .now
        if entry.updatedAt == targetUpdate {
            entry.publishStatus = .published
            context.delete(operation)
        } else {
            entry.publishStatus = .needsUpdate
            operation.requestedEntryUpdate = entry.updatedAt
            operation.attemptCount = 0
            operation.nextAttemptAt = .distantPast
            operation.lastError = ""
        }
        try context.save()
    }

    private func finishUnpublish(_ operation: PublishOperation) throws {
        let destinationID = operation.destinationID
        if let entry = try entry(id: operation.entryID) {
            entry.publishStatus = .notPublished
            entry.remoteID = nil
            entry.publishedAt = nil
            entry.publishDestinationID = nil
        }
        context.delete(operation)
        try context.save()
        try removeDestinationIfUnused(destinationID)
    }

    private func entry(id: UUID) throws -> Entry? {
        try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
    }

    private func metadataCache(for entryID: UUID) throws -> EntryMetadataCache {
        try EntryMetadataCache.findOrCreate(for: entryID, in: context)
    }

    private func removeDestinationIfUnused(_ id: UUID) throws {
        let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.publishDestinationID == id }))
        let operations = try context.fetch(FetchDescriptor<PublishOperation>(predicate: #Predicate { $0.destinationID == id }))
        guard entries.isEmpty, operations.isEmpty else { return }
        if let destination = try context.fetch(
            FetchDescriptor<PublishDestination>(predicate: #Predicate { $0.id == id })
        ).first {
            context.delete(destination)
            try context.save()
        }
    }

    private func retryDelay(attempt: Int) -> TimeInterval {
        min(3600, pow(2, Double(min(attempt, 10))) * 5)
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = nil
        guard isActive,
              let operations = try? context.fetch(FetchDescriptor<PublishOperation>()) else { return }
        let now = Date.now
        let eligibleDates = operations.compactMap { operation in
            api(for: operation.destinationID) == nil ? nil : operation.nextAttemptAt
        }
        guard let due = Self.nextRetryDate(eligibleDates, after: now) else { return }
        let delay = max(0.05, due.timeIntervalSince(now))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.retryTask = nil
            await self.processPending()
        }
    }
}

nonisolated enum PublishingError: LocalizedError {
    case differentDestination
    case nothingToMove
    case notTheSameWebsite
    case photosNotConfirmed
    case removalNotConfirmed
    case remoteEntryNotFound

    var errorDescription: String? {
        switch self {
        case .differentDestination:
            "This entry is bound to its original website. Unpublish it there before changing destinations."
        case .nothingToMove:
            "There is nothing published to move."
        case .notTheSameWebsite:
            "That address did not return the journal Journey already published. Check it serves the same website before moving."
        case .photosNotConfirmed:
            "The website has not confirmed every photo yet. Journey will retry."
        case .removalNotConfirmed:
            "The website has not confirmed removal yet. Journey will retry."
        case .remoteEntryNotFound:
            "Journey could not confirm the existing online entry, so it did not replace its photos."
        }
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
