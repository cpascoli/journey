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

struct AssetGrid: View {
    let ids: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
            ForEach(ids, id: \.self) { id in
                AssetThumbnail(localIdentifier: id, size: 80)
                    .overlay(alignment: .topTrailing) {
                        Button("Remove", systemImage: "xmark.circle.fill") { onRemove(id) }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .buttonStyle(.borderless)
                            .padding(2)
                    }
            }
        }
    }
}
