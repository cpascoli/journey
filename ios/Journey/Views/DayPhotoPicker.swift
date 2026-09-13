import Photos
import SwiftUI

/// Picks from the photos and videos taken on one day. The system picker can't
/// filter by date, but the app has full library access, so it lists the day itself.
struct DayPhotoPicker: View {
    let day: Date
    @Binding var selection: [String]

    @State private var assets: [PHAsset] = []
    @State private var isLoaded = false
    @Environment(\.dismiss) private var dismiss

    private let side: CGFloat = 118
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: side), spacing: 6)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        cell(for: asset.localIdentifier)
                    }
                }
                .padding(12)
            }
            .overlay {
                if isLoaded && assets.isEmpty {
                    ContentUnavailableView(
                        "Nothing From This Day",
                        systemImage: "photo.on.rectangle",
                        description: Text("No photos or videos were taken on \(day.formatted(date: .long, time: .omitted)).")
                    )
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                assets = await PhotoLibrary.requestAccess() ? PhotoLibrary.assets(on: day) : []
                isLoaded = true
            }
        }
    }

    private func cell(for id: String) -> some View {
        let isSelected = selection.contains(id)
        return Button {
            if isSelected {
                selection.removeAll { $0 == id }
            } else {
                selection.append(id)
            }
        } label: {
            AssetThumbnail(localIdentifier: id, size: side)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.clear)
                        .font(.title3)
                        .shadow(radius: 2)
                        .padding(6)
                }
                .opacity(isSelected ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
