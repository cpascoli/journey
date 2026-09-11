import Photos
import SwiftUI

/// A day of the journal, laid out to be read like a page: read mode, as opposed to the editor.
struct JournalPageView: View {
    let day: Date
    let entries: [Entry]
    let journal: Journal

    @State private var showTranslation = false
    @State private var editing: EntryDraft?
    @State private var viewer: MediaViewerRequest?

    private var places: [String] {
        var seen = Set<String>()
        return entries.compactMap(\.placeName).filter { seen.insert($0).inserted }
    }

    private var dayMedia: [String] {
        var seen = Set<String>()
        return entries.flatMap(\.mediaAssetIDs).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                if entries.isEmpty {
                    emptyPage
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Text("✦")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                        EntryPageSection(
                            entry: entry,
                            showTranslation: showTranslation,
                            onOpenMedia: { id in viewer = MediaViewerRequest(ids: dayMedia, start: id) },
                            onEdit: { editing = EntryDraft(entry: entry) }
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.journalPaper)
        .sheet(item: $editing) { draft in
            EntryEditorView(draft: draft, journal: journal)
        }
        .fullScreenCover(item: $viewer) { request in
            MediaViewer(ids: request.ids, start: request.start)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text(day.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
            if !places.isEmpty {
                Text(places.joined(separator: " · "))
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            if entries.contains(where: { !$0.translationLanguage.isEmpty }) {
                Button {
                    withAnimation { showTranslation.toggle() }
                } label: {
                    Label(showTranslation ? "Show Original" : "Show Translation", systemImage: "translate")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 6)
            }
        }
    }

    private var emptyPage: some View {
        VStack(spacing: 14) {
            Text("Nothing written on this day.")
                .font(.system(.body, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
            Button("Write About This Day", systemImage: "square.and.pencil") {
                editing = EntryDraft(day: day)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

private struct EntryPageSection: View {
    let entry: Entry
    let showTranslation: Bool
    let onOpenMedia: (String) -> Void
    let onEdit: () -> Void

    private var translated: Bool { showTranslation && !entry.translationLanguage.isEmpty }
    private var title: String { pick(entry.translatedTitle, entry.title) }
    private var notes: String { pick(entry.translatedBody, entry.body) }
    private var story: String { pick(entry.translatedNarrative, entry.narrative) }

    private func pick(_ translation: String, _ original: String) -> String {
        translated && !translation.isEmpty ? translation : original
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text([entry.date.formatted(date: .omitted, time: .shortened), entry.placeName]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                    .uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit", systemImage: "pencil", action: onEdit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }

            if !title.isEmpty {
                Text(title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
            }

            media

            if !notes.isEmpty {
                Text(notes)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(6)
            }

            if !story.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.45))
                        .frame(width: 2)
                    Text(story)
                        .font(.system(.body, design: .serif))
                        .italic()
                        .lineSpacing(5)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        let ids = entry.mediaAssetIDs
        if let first = ids.first {
            Button { onOpenMedia(first) } label: {
                AssetImage(localIdentifier: first)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pageMedia")
            if ids.count > 1 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(ids.dropFirst(), id: \.self) { id in
                        Button { onOpenMedia(id) } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { AssetThumbnail(localIdentifier: id, size: nil) }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// A photo or video poster frame shown whole, at its own aspect ratio.
private struct AssetImage: View {
    let localIdentifier: String

    @State private var image: UIImage?
    @State private var isVideo = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 480)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
        }
        .task(id: localIdentifier) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return }
            isVideo = asset.mediaType == .video
            image = await PhotoLibrary.image(for: asset, fitting: CGSize(width: 1400, height: 1400))
        }
    }
}

struct MediaViewerRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    let start: String
}

extension Color {
    /// Warm paper in light mode, warm charcoal in dark mode.
    static let journalPaper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
            : UIColor(red: 0.985, green: 0.969, blue: 0.937, alpha: 1)
    })
}
