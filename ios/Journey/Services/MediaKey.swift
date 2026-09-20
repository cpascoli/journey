import CryptoKit
import Foundation

/// The key the website stores a media item under.
///
/// Photos identifiers contain slashes, so the key is a hash of one rather than
/// the identifier itself — which also means the website never learns a Photos
/// identifier. Photos and videos share this, because an entry's `media_keys`
/// is one ordered list regardless of kind.
nonisolated enum MediaKey {
    static func key(for localIdentifier: String) -> String {
        SHA256.hash(data: Data(localIdentifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
