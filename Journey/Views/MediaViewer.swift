import AVKit
import Photos
import SwiftUI

/// Full-screen photos and videos, swiping between them. Photos zoom with a pinch or a double tap.
struct MediaViewer: View {
    let ids: [String]
    @State private var selection: String
    @Environment(\.dismiss) private var dismiss

    init(ids: [String], start: String) {
        self.ids = ids
        _selection = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(ids, id: \.self) { id in
                    MediaPage(localIdentifier: id, isCurrent: id == selection)
                        .tag(id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                Spacer()
                if ids.count > 1, let index = ids.firstIndex(of: selection) {
                    Text("\(index + 1) of \(ids.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal)
        }
        .statusBarHidden()
    }
}

private struct MediaPage: View {
    let localIdentifier: String
    let isCurrent: Bool

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoom)
                    .gesture(pan, including: scale > 1 ? .all : .subviews)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring) {
                            if scale > 1 {
                                resetZoom()
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localIdentifier) { await load() }
        .onChange(of: isCurrent) { _, current in
            guard !current else { return }
            player?.pause()
            resetZoom()
        }
        .onDisappear { player?.pause() }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    withAnimation(.spring) { resetZoom() }
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func load() async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return }
        if asset.mediaType == .video {
            isVideo = true
            if let item = await PhotoLibrary.playerItem(for: asset) {
                player = AVPlayer(playerItem: item)
            }
        } else {
            image = await PhotoLibrary.image(for: asset, fitting: CGSize(width: 2400, height: 2400))
        }
    }
}
