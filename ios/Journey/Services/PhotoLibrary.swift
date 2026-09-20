import AVFoundation
import Photos
import UIKit

enum PhotoLibrary {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
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
