import Photos
import SwiftData
import SwiftUI

extension EntryVisibility {
    var title: String {
        switch self {
        case .onlyMe: "Only Me"
        case .invites: "People I Invite"
        }
    }
}

extension LocationPrecision {
    var title: String {
        switch self {
        case .exact: "Exact Place"
        case .neighborhood: "Neighbourhood"
        case .city: "City"
        case .hidden: "Hidden"
        }
    }
}

extension PublishStatus {
    var symbol: String {
        switch self {
        case .notPublished: "globe"
        case .published: "checkmark.circle"
        case .needsUpdate: "arrow.triangle.2.circlepath"
        }
    }
}

/// Publishing one entry to the website: who can read it, how precisely its
/// location is shown, and publish, update or unpublish.
struct PublishSheet: View {
    let entry: Entry

    @State private var visibility: EntryVisibility
    @State private var precision: LocationPrecision
    @State private var report: Publisher.Report?
    @State private var errorMessage: String?
    @State private var isConfirmingUnpublish = false
    @State private var api = JourneyAPI.configured()
    @Environment(\.dismiss) private var dismiss
    @Environment(Publisher.self) private var publisher
    @Query private var metadataCaches: [EntryMetadataCache]

    init(entry: Entry) {
        self.entry = entry
        _visibility = State(initialValue: entry.visibility)
        _precision = State(initialValue: entry.sharedLocationPrecision)
    }

    private var isPublished: Bool { entry.isPublicationBound }
    private var cachedLocality: String? {
        guard let latitude = entry.latitude, let longitude = entry.longitude else { return nil }
        return metadataCaches.first {
            $0.entryID == entry.id && $0.matches(latitude: latitude, longitude: longitude)
        }?.locality
    }
    private var media: (photos: Int, videos: Int, longVideos: Int, unavailable: Int) {
        let media = Publisher.media(of: entry)
        return (
            media.photos.count,
            media.videos.count,
            media.videos.count { $0.duration > VideoExport.maxDuration },
            media.unavailable
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if api == nil {
                    Section {
                        Label("Add your website and owner key in Settings → Website to publish.", systemImage: "key")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Status", value: statusText)
                }

                Section {
                    Picker("Who Can Read It", selection: $visibility) {
                        ForEach(EntryVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text(visibilityFooter)
                }

                if entry.placeName != nil || entry.latitude != nil {
                    Section {
                        Picker("Location", selection: $precision) {
                            ForEach(LocationPrecision.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } footer: {
                        Text(precisionFooter)
                    }
                }

                if !entry.mediaAssetIDs.isEmpty {
                    Section {
                        LabeledContent("Photos", value: "\(media.photos)")
                    } footer: {
                        Text(mediaFooter)
                    }
                }

                Section {
                    Button(isPublished ? "Update Website" : "Publish", systemImage: "arrow.up.circle", action: publish)
                        .disabled(api == nil || publisher.isWorking)
                    if isPublished {
                        Button("Unpublish", systemImage: "trash", role: .destructive) { isConfirmingUnpublish = true }
                            .disabled(api == nil || publisher.isWorking)
                    }
                } footer: {
                    if let progress = progressText {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(progress)
                        }
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if let report, let text = reportText(report) {
                        Text(text)
                    }
                }
            }
            .navigationTitle("Publish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(publisher.isWorking)
                }
            }
            .interactiveDismissDisabled(publisher.isWorking)
            .confirmationDialog("Unpublish this entry?", isPresented: $isConfirmingUnpublish, titleVisibility: .visible) {
                Button("Unpublish", role: .destructive, action: unpublish)
            } message: {
                Text("It's removed from the website with its photos. It stays in your journal.")
            }
        }
    }

    private var statusText: String {
        switch entry.publishStatus {
        case .notPublished: "Not published"
        case .published: "Published"
        case .needsUpdate: "Changed since publishing"
        }
    }

    private var visibilityFooter: String {
        switch visibility {
        case .onlyMe:
            return "On the website, but only you can read it."
        case .invites:
            let tags = entry.sortedTags.map(\.name)
            if tags.isEmpty {
                return "It has no tags, so everyone you invite can read it."
            }
            return "Only invites that include \(tags.formatted(.list(type: .and))) can read it."
        }
    }

    private var precisionFooter: String {
        switch precision {
        case .exact: "Shows the place's name and exact position."
        case .neighborhood: "Shows the place's name, with its position rounded to about 1 km."
        case .city:
            if let cachedLocality {
                "Shows \(cachedLocality), with its position rounded to about 10 km."
            } else {
                "Shows only the city, with its position rounded to about 10 km."
            }
        case .hidden: "No location is sent to the website."
        }
    }

    private var mediaFooter: String {
        var parts = ["Photos are uploaded at up to \(PhotoExport.maxPixelSize) pixels, with their location and camera details removed."]
        let media = media
        let sendable = media.videos - media.longVideos
        if sendable > 0 {
            parts.append(sendable == 1
                ? "The video is re-encoded at 720p, with its location removed."
                : "The \(sendable) videos are re-encoded at 720p, with their locations removed.")
        }
        if media.longVideos > 0 {
            let limit = Int(VideoExport.maxDuration)
            parts.append(media.longVideos == 1
                ? "One video is longer than \(limit) seconds and stays on your iPhone."
                : "\(media.longVideos) videos are longer than \(limit) seconds and stay on your iPhone.")
        }
        if media.unavailable > 0 {
            parts.append("\(media.unavailable) can't be read from your library.")
        }
        return parts.joined(separator: " ")
    }

    private var progressText: String? {
        switch publisher.step {
        case .idle: nil
        case .tags: "Sending tags…"
        case .entry: "Sending the entry…"
        case let .exporting(index, count): "Preparing video \(index) of \(count)…"
        case let .media(index, count): "Uploading \(index) of \(count)…"
        case .removing: "Removing from the website…"
        }
    }

    private func reportText(_ report: Publisher.Report) -> String? {
        if report.failedPhotos > 0 {
            return report.failedPhotos == 1
                ? "One photo couldn't be prepared. Update again to retry it."
                : "\(report.failedPhotos) photos couldn't be prepared. Update again to retry them."
        }
        if report.failedVideos > 0 {
            return report.failedVideos == 1
                ? "One video couldn't be uploaded. Update again to retry it."
                : "\(report.failedVideos) videos couldn't be uploaded. Update again to retry them."
        }
        if report.skippedVideos > 0 {
            return report.skippedVideos == 1
                ? "One video was left off: it's too long or too large to upload."
                : "\(report.skippedVideos) videos were left off: too long or too large to upload."
        }
        return entry.publishStatus == .published ? "Up to date on the website." : nil
    }

    private func publish() {
        guard let api else { return }
        // Saved only now, when publishing: choosing a wider audience takes effect on this tap, not before.
        entry.visibility = visibility
        entry.sharedLocationPrecision = precision
        errorMessage = nil
        report = nil
        Task {
            do {
                report = try await publisher.publish(entry, with: api)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func unpublish() {
        guard let api else { return }
        errorMessage = nil
        report = nil
        Task {
            do {
                try await publisher.unpublish(entry, with: api)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
