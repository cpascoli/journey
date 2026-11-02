import AVFoundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum PhotoLibrary {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    enum ImportError: LocalizedError {
        case unsupported(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): "“\(name)” isn't a photo or video."
            case .failed(let name): "“\(name)” could not be added to your photo library."
            }
        }
    }

    /// Adds files picked outside the library (Files, iCloud Drive, a USB
    /// drive) to the Photos library and returns their identifiers, in order.
    ///
    /// Entries only ever refer to Photos assets, so a file has to become one
    /// first: that keeps publishing, thumbnails and media keys unchanged. The
    /// file is copied, so the original stays where it was.
    nonisolated static func importFiles(_ urls: [URL]) async throws -> [String] {
        var identifiers: [String] = []
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
            let resourceType: PHAssetResourceType
            if type?.conforms(to: .image) == true {
                resourceType = .photo
            } else if type?.conforms(to: .movie) == true {
                resourceType = .video
            } else {
                throw ImportError.unsupported(name)
            }
            // Photos takes ownership of the file it is given, so hand it a copy.
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            let created = CreatedAsset()
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = name
                    options.shouldMoveFile = true
                    request.addResource(with: resourceType, fileURL: copy, options: options)
                    created.identifier = request.placeholderForCreatedAsset?.localIdentifier
                }
            } catch {
                try? FileManager.default.removeItem(at: copy)
                throw ImportError.failed(name)
            }
            guard let identifier = created.identifier else { throw ImportError.failed(name) }
            identifiers.append(identifier)
        }
        return identifiers
    }

    /// Carries the placeholder's identifier out of the change block, which
    /// Photos runs on its own queue.
    private final class CreatedAsset: @unchecked Sendable {
        nonisolated(unsafe) var identifier: String?
    }

    static func assets(on day: Date) -> [PHAsset] {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return assets(in: [DateInterval(start: start, end: end)])
    }

    static func assets(for localDay: String, timeZoneIdentifiers: [String]) -> [PHAsset] {
        assets(in: LocalDay.intervals(for: localDay, timeZoneIdentifiers: timeZoneIdentifiers))
    }

    static func assets(in intervals: [DateInterval]) -> [PHAsset] {
        var byID: [String: PHAsset] = [:]
        for interval in intervals {
            for asset in assets(in: interval) {
                byID[asset.localIdentifier] = asset
            }
        }
        return byID.values.sorted { lhs, rhs in
            let leftDate = lhs.creationDate ?? .distantPast
            let rightDate = rhs.creationDate ?? .distantPast
            return leftDate == rightDate
                ? lhs.localIdentifier < rhs.localIdentifier
                : leftDate < rightDate
        }
    }

    private static func assets(in interval: DateInterval) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)",
            interval.start as NSDate, interval.end as NSDate,
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    /// The whole image, scaled to fit `size` (in pixels).
    static func image(for asset: PHAsset, fitting size: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    static func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    static func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        // highQualityFormat guarantees a single callback, which the continuation requires.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
