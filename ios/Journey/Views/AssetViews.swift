import Photos
import SwiftUI

struct AssetThumbnail: View {
    let localIdentifier: String
    /// Fixed square side, or nil to fill whatever frame the parent gives it.
    var size: CGFloat? = 72

    @State private var image: UIImage?
    @State private var isVideo = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
            if isVideo {
                Image(systemName: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .frame(minWidth: 0, maxWidth: size == nil ? .infinity : nil, minHeight: 0, maxHeight: size == nil ? .infinity : nil)
        .clipped()
        .clipShape(.rect(cornerRadius: 8))
        .task(id: localIdentifier) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return }
            isVideo = asset.mediaType == .video
            image = await PhotoLibrary.thumbnail(for: asset, side: (size ?? 200) * displayScale)
        }
    }
}

struct AssetStrip: View {
    let ids: [String]
    var size: CGFloat = 72

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(ids, id: \.self) { AssetThumbnail(localIdentifier: $0, size: size) }
            }
        }
        .frame(height: size)
    }
}

/// One attached photo or video, as a row: a thumbnail and what it is.
///
/// A row rather than a tile so the editor can use the list behaviour people
/// already know — swipe to delete, drag the handle to reorder — instead of a
/// small overlay button that is easy to miss.
struct AssetRow: View {
    let localIdentifier: String

    @State private var caption = "Photo"

    var body: some View {
        HStack(spacing: 12) {
            AssetThumbnail(localIdentifier: localIdentifier, size: 44)
            Text(caption)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .task(id: localIdentifier) {
            guard let asset = PHAsset.fetchAssets(
                withLocalIdentifiers: [localIdentifier], options: nil
            ).firstObject else {
                // Still listed, but no longer in the library.
                caption = "Unavailable"
                return
            }
            let kind = asset.mediaType == .video ? "Video" : "Photo"
            guard let taken = asset.creationDate else {
                caption = kind
                return
            }
            caption = "\(kind) · \(taken.formatted(date: .omitted, time: .shortened))"
        }
    }
}
