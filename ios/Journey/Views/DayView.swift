import Photos
import SwiftData
import SwiftUI

struct DayView: View {
    @Binding var day: Date
    let journal: Journal

    @Query private var entries: [Entry]
    @Query private var visits: [Visit]
    @State private var assets: [PHAsset] = []
    @State private var editorDraft: EntryDraft?
    @State private var publishedToDelete: Entry?
    @Environment(LocationService.self) private var location
    @Environment(\.modelContext) private var context

    init(day: Binding<Date>, journal: Journal) {
        _day = day
        self.journal = journal
        let start = day.wrappedValue
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(filter: #Predicate<Entry> { $0.date >= start && $0.date < end }, sort: \Entry.date)
        _visits = Query(filter: #Predicate<Visit> { $0.arrival >= start && $0.arrival < end }, sort: \Visit.arrival)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var journalEntries: [Entry] {
        entries.filter { $0.journal?.id == journal.id }
    }

    var body: some View {
        let timeline = DayTimeline(visits: visits, assets: assets)
        List {
            if location.isTrackingDenied {
                Section {
                    Label("Location access is off, so places aren't being recorded.", systemImage: "location.slash")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Entries") {
                if journalEntries.isEmpty {
                    Text("No entries yet").foregroundStyle(.secondary)
                }
                ForEach(journalEntries) { entry in
                    Button {
                        editorDraft = EntryDraft(entry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let chosen = offsets.map { journalEntries[$0] }
                    // Deleting a published entry here would leave it online.
                    if let published = chosen.first(where: { $0.publishStatus != .notPublished }) {
                        publishedToDelete = published
                    } else {
                        chosen.forEach(context.delete)
                    }
                }
            }

            if !timeline.stops.isEmpty {
                Section("Places") {
                    ForEach(timeline.stops) { stop in
                        StopRow(stop: stop) { editorDraft = EntryDraft(stop: stop) }
                    }
                }
            }

            if !timeline.looseAssetIDs.isEmpty {
                Section("Other photos & videos") {
                    AssetStrip(ids: timeline.looseAssetIDs)
                }
            }
        }
        .navigationTitle(day.formatted(.dateTime.weekday(.abbreviated).month().day()))
        // Day navigation lives in the top bar: the floating tab bar covers a bottom bar.
        .toolbar {
            if !isToday {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { day = Calendar.current.startOfDay(for: .now) }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Previous Day", systemImage: "chevron.left") { shiftDay(by: -1) }
                Button("Next Day", systemImage: "chevron.right") { shiftDay(by: 1) }
                    .disabled(isToday)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Entry", systemImage: "plus") { editorDraft = EntryDraft(day: day) }
            }
        }
        .sheet(item: $editorDraft) { draft in
            EntryEditorView(draft: draft, journal: journal)
        }
        .alert(
            "Unpublish It First",
            isPresented: Binding(get: { publishedToDelete != nil }, set: { if !$0 { publishedToDelete = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("“\(publishedToDelete.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "")” is on your website. Unpublish it from its journal page in Calendar before deleting it, or it would stay online.")
        }
        .task(id: day) {
            assets = await PhotoLibrary.requestAccess() ? PhotoLibrary.assets(on: day) : []
            // Days before tracking started (or places it missed) get their places from the photos.
            let loose = Set(DayTimeline(visits: visits, assets: assets).looseAssetIDs)
            let created = PhotoPlaces.addVisits(
                for: assets.filter { loose.contains($0.localIdentifier) },
                extending: visits,
                in: context
            )
            await PlaceNamer.nameUnnamed(visits + created, in: context)
        }
        .task {
            location.requestAuthorizationIfNeeded()
        }
    }

    private func shiftDay(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: day) {
            day = next
        }
    }
}

private struct EntryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.headline)
                if entry.publishStatus != .notPublished {
                    Image(systemName: entry.publishStatus.symbol)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(entry.publishStatus == .published ? "Published" : "Changed since publishing")
                }
            }
            Text([entry.date.formatted(date: .omitted, time: .shortened), entry.placeName]
                .compactMap { $0 }
                .joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !entry.body.isEmpty {
                Text(entry.body).lineLimit(2)
            }
            if !entry.narrative.isEmpty {
                Text(entry.narrative)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if !entry.sortedTags.isEmpty {
                FlowLayout {
                    ForEach(entry.sortedTags) { TagChip(tag: $0) }
                }
            }
            if !entry.mediaAssetIDs.isEmpty {
                AssetStrip(ids: entry.mediaAssetIDs, size: 48)
            }
        }
        .contentShape(.rect)
    }
}

private struct StopRow: View {
    let stop: DayTimeline.Stop
    let onWrite: () -> Void

    private var timeRange: String {
        let visit = stop.visit
        let arrival = visit.arrival.formatted(date: .omitted, time: .shortened)
        var text: String
        if let departure = visit.departure {
            let end = departure.formatted(date: .omitted, time: .shortened)
            text = end == arrival ? arrival : "\(arrival) – \(end)"
        } else {
            text = "\(arrival) – now"
        }
        if visit.source == .photos {
            text += " · from photos"
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(stop.visit.placeName ?? "Unknown place").font(.headline)
                    Text(timeRange).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Write about this place", systemImage: "square.and.pencil", action: onWrite)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            if !stop.assetIDs.isEmpty {
                AssetStrip(ids: stop.assetIDs)
            }
        }
    }
}
