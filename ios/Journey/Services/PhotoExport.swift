import CryptoKit
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Turns library photos into the JPEGs the website accepts: resized, with the
/// orientation baked into the pixels, and with every metadata segment that
/// could carry a location removed. The website refuses a photo that still has
/// one, and never strips metadata itself.
enum PhotoExport {
    nonisolated struct Photo: Sendable {
        let jpeg: Data
        let width: Int
        let height: Int
    }

    /// Longest side, in pixels.
    nonisolated static let maxPixelSize = 2048
    /// The website's `MAX_PHOTO_BYTES`.
    nonisolated static let maxBytes = 5 * 1024 * 1024

    /// The key the website stores a photo under. Photos identifiers contain slashes, so a hash.
    nonisolated static func key(for localIdentifier: String) -> String {
        SHA256.hash(data: Data(localIdentifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The photo as the library shows it (with the user's edits), ready to upload; nil if it can't be read.
    static func photo(for asset: PHAsset) async -> Photo? {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) { jpeg(from: data) }.value
    }

    /// Re-encodes any image ImageIO reads (HEIC, JPEG, …) as a metadata-free JPEG.
    nonisolated static func jpeg(from data: Data) -> Photo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // The EXIF orientation is about to be stripped, so apply it to the pixels.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        for quality in [0.82, 0.7, 0.55] {
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination),
                  let stripped = JPEGMetadata.stripped(encoded as Data),
                  JPEGMetadata.locationCarriers(in: stripped).isEmpty else { return nil }
            if stripped.count <= maxBytes {
                return Photo(jpeg: stripped, width: image.width, height: image.height)
            }
        }
        return nil
    }
}

/// The JPEG segments that can say where a photo was taken: APP1 (EXIF, which
/// holds GPS, and XMP, which can repeat it) and APP13 (IPTC, which can name the
/// place). Mirrors `findPhotoMetadata` in web/src/lib/owner/media.ts; keep the
/// two in step.
nonisolated enum JPEGMetadata {
    private static let app1: UInt8 = 0xE1
    private static let app13: UInt8 = 0xED
    private static let comment: UInt8 = 0xFE

    /// The JPEG without APP1, APP13 and comment segments; every other segment and
    /// the image data are copied as they are. Nil if the bytes aren't a JPEG this can walk.
    static func stripped(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        out.reserveCapacity(bytes.count)
        var result: Data?
        walk(bytes) { piece in
            switch piece {
            case let .marker(range):
                out.append(contentsOf: bytes[range])
            case let .segment(marker, range):
                if ![app1, app13, comment].contains(marker) {
                    out.append(contentsOf: bytes[range])
                }
            case let .imageData(from):
                out.append(contentsOf: bytes[from...])
                result = Data(out)
            }
        }
        return result
    }

    /// What `findPhotoMetadata` on the website would find: "exif", "xmp", "app1" or "iptc".
    static func locationCarriers(in data: Data) -> [String] {
        let bytes = [UInt8](data)
        var found: [String] = []
        walk(bytes) { segment in
            guard case let .segment(marker, range) = segment else { return }
            let body = bytes[(range.lowerBound + 4)..<range.upperBound]
            if marker == app1 {
                if body.starts(with: Array("Exif\0".utf8)) {
                    found.append("exif")
                } else if body.starts(with: Array("http://ns.adobe.com/xap/".utf8)) {
                    found.append("xmp")
                } else {
                    found.append("app1")
                }
            } else if marker == app13 {
                found.append("iptc")
            }
        }
        return found
    }

    private enum Piece {
        /// A marker without a length (RSTn, TEM), including its fill bytes.
        case marker(Range<Int>)
        /// A marker with its length and body.
        case segment(UInt8, Range<Int>)
        /// Start of scan or end of image, from its offset to the end of the file.
        case imageData(Int)
    }

    /// Walks the marker segments up to the image data, as the website does.
    /// Stops without an `.imageData` piece if the structure is broken.
    private static func walk(_ bytes: [UInt8], _ visit: (Piece) -> Void) {
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { return }
            let start = i
            // Markers may be preceded by any number of 0xFF fill bytes.
            while bytes[i + 1] == 0xFF, i + 2 < bytes.count { i += 1 }
            let marker = bytes[i + 1]
            if marker == 0xDA || marker == 0xD9 {
                visit(.imageData(start))
                return
            }
            if marker == 0x01 || (0xD0...0xD8).contains(marker) {
                visit(.marker(start..<(i + 2)))
                i += 2
                continue
            }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return }
            visit(.segment(marker, i..<(i + 2 + length)))
            i += 2 + length
        }
    }
}
