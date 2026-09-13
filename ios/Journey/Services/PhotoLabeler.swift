import Photos
import UIKit
import Vision

/// Describes what's in an entry's photos and videos, so the text-only language
/// model has something to go on.
enum PhotoLabeler {
    private static let maxItems = 8
    private static let minConfidence: Float = 0.35

    /// Scene labels across the items (a still frame for videos), most prominent first.
    static func labels(for assetIDs: [String], limit: Int = 12) async -> [String] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        let assets = result.objects(at: IndexSet(integersIn: 0..<min(result.count, maxItems)))
        let request = ClassifyImageRequest()
        var scores: [String: Float] = [:]
        for asset in assets {
            guard let image = await PhotoLibrary.thumbnail(for: asset, side: 512)?.cgImage,
                  let observations = try? await request.perform(on: image) else { continue }
            for observation in observations where observation.confidence >= minConfidence {
                scores[observation.identifier, default: 0] += observation.confidence
            }
        }
        return scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key.replacingOccurrences(of: "_", with: " ") }
    }
}
