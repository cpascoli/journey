import AVFoundation
import Foundation
import Photos

/// Turns library videos into the MP4s the website accepts: H.264 at 720p, with
/// every metadata atom that could carry a location removed, and the header
/// moved to the front.
///
/// The website refuses a video that still has a location, and never strips one
/// itself — the same rule as `PhotoExport`. It also refuses a file whose `moov`
/// atom is not at the front, because it verifies the upload by reading only the
/// head: `shouldOptimizeForNetworkUse` is what puts it there, so it is not an
/// optimisation here but a requirement.
enum VideoExport {
    nonisolated struct Video: Sendable {
        /// A file in the temporary directory. Call `discard` when the upload is done.
        let fileURL: URL
        let byteCount: Int
        let durationSeconds: Double
        let width: Int
        let height: Int
    }

    enum Failure: Error, Equatable {
        case tooLong(seconds: Double)
        case tooLarge(bytes: Int)
        case unreadable
    }

    /// The website's `MAX_VIDEO_BYTES`.
    nonisolated static let maxBytes = 60 * 1024 * 1024
    /// The 720p preset runs at roughly 4 Mbps, so 90 seconds lands near 45 MB.
    /// Checked before exporting, which keeps most clips from being re-encoded
    /// only to be refused by `maxBytes` afterwards.
    nonisolated static let maxDuration: TimeInterval = 90

    nonisolated static func key(for localIdentifier: String) -> String {
        MediaKey.key(for: localIdentifier)
    }

    /// The video re-encoded for the website, or the reason it can't be sent.
    static func video(for asset: PHAsset) async -> Result<Video, Failure> {
        if asset.duration > maxDuration {
            return .failure(.tooLong(seconds: asset.duration))
        }
        guard let source = await avAsset(for: asset) else { return .failure(.unreadable) }

        // 1280x720 H.264/AAC: the presets that name a size are H.264, which
        // every browser plays. The HEVC presets are not safe to embed.
        guard let session = AVAssetExportSession(asset: source, presetName: AVAssetExportPreset1280x720) else {
            return .failure(.unreadable)
        }
        // Drops the QuickTime location atoms along with everything else the
        // camera wrote. The website rejects the upload if any survive.
        session.metadata = []
        session.shouldOptimizeForNetworkUse = true

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("journey-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(.unreadable)
        }

        guard let shape = await shape(of: outputURL) else {
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(.unreadable)
        }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? nil
        guard let byteCount else {
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(.unreadable)
        }
        guard byteCount <= maxBytes else {
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(.tooLarge(bytes: byteCount))
        }
        return .success(Video(
            fileURL: outputURL,
            byteCount: byteCount,
            durationSeconds: shape.duration,
            width: shape.width,
            height: shape.height
        ))
    }

    /// Temporary files are the caller's to clean up: an upload may retry.
    nonisolated static func discard(_ video: Video) {
        try? FileManager.default.removeItem(at: video.fileURL)
    }

    private static func avAsset(for asset: PHAsset) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    /// Display dimensions and duration of the exported file. The preferred
    /// transform is applied, so a portrait clip reports portrait dimensions —
    /// matching what the website reads back out of the file's `tkhd` matrix.
    private static func shape(
        of url: URL
    ) async -> (width: Int, height: Int, duration: Double)? {
        let exported = AVURLAsset(url: url)
        guard let track = try? await exported.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await exported.load(.duration) else { return nil }
        let displaySize = naturalSize.applying(transform)
        let width = Int(abs(displaySize.width).rounded())
        let height = Int(abs(displaySize.height).rounded())
        guard width > 0, height > 0 else { return nil }
        return (width, height, duration.seconds)
    }
}
