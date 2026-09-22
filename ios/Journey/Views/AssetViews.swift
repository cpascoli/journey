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
    /// Supplied where the order matters; omit it and the grid is not reorderable.
    var onReorder: (([String]) -> Void)?

    /// Which item is being dragged, so the rest can show where it would land.
    @State private var dragging: String?

    private var isReorderable: Bool { onReorder != nil && ids.count > 1 }

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
                    .opacity(dragging == id ? 0.35 : 1)
                    // A long press starts the drag, so this does not fight
                    // the form's scrolling or the remove button's tap.
                    .draggable(id) {
                        AssetThumbnail(localIdentifier: id, size: 80)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .dropDestination(for: String.self) { dropped, _ in
                        guard isReorderable, let moved = dropped.first, let onReorder else { return false }
                        onReorder(MediaOrder.moving(moved, before: id, in: ids))
                        dragging = nil
                        return true
                    } isTargeted: { targeted in
                        if targeted { dragging = nil }
                    }
            }

            if isReorderable {
                // Dropping always inserts *before* something, so without a
                // target past the last item nothing could be made last.
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Move to the end")
                    }
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let moved = dropped.first, let onReorder else { return false }
                        onReorder(MediaOrder.movingToEnd(moved, in: ids))
                        dragging = nil
                        return true
                    }
            }
        }
    }
}
