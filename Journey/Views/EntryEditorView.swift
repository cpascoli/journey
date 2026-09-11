import PhotosUI
import SwiftData
import SwiftUI

struct EntryDraft: Identifiable {
    let id = UUID()
    var entry: Entry?
    var title = ""
    var body = ""
    var date = Date.now
    var placeName = ""
    var latitude: Double?
    var longitude: Double?
    var assetIDs: [String] = []
    var visit: Visit?

    init(day: Date) {
        date = Calendar.current.isDateInToday(day)
            ? .now
            : Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
    }

    init(entry: Entry) {
        self.entry = entry
        title = entry.title
        body = entry.body
        date = entry.date
        placeName = entry.placeName ?? ""
        latitude = entry.latitude
        longitude = entry.longitude
        assetIDs = entry.mediaAssetIDs
    }

    init(stop: DayTimeline.Stop) {
        visit = stop.visit
        date = stop.visit.arrival
        placeName = stop.visit.placeName ?? ""
        latitude = stop.visit.latitude
        longitude = stop.visit.longitude
        assetIDs = stop.assetIDs
    }
}

struct EntryEditorView: View {
    let journal: Journal
    @State private var draft: EntryDraft
    @State private var pickerItems: [PhotosPickerItem] = []
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(draft: EntryDraft, journal: Journal) {
        _draft = State(initialValue: draft)
        self.journal = journal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Place", text: $draft.placeName)
                    DatePicker("When", selection: $draft.date)
                }

                Section("Notes") {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 160)
                }

                Section("Photos & videos") {
                    if !draft.assetIDs.isEmpty {
                        AssetGrid(ids: draft.assetIDs) { id in
                            draft.assetIDs.removeAll { $0 == id }
                        }
                    }
                    PhotosPicker(
                        selection: $pickerItems,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Label("Add Photos & Videos", systemImage: "photo.badge.plus")
                    }
                }
            }
            .navigationTitle(draft.entry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                let newIDs = items.compactMap(\.itemIdentifier).filter { !draft.assetIDs.contains($0) }
                draft.assetIDs.append(contentsOf: newIDs)
                pickerItems = []
            }
        }
    }

    private func save() {
        let entry: Entry
        if let existing = draft.entry {
            entry = existing
        } else {
            entry = Entry()
            context.insert(entry)
            entry.journal = journal
        }
        let place = draft.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.body = draft.body
        entry.date = draft.date
        entry.placeName = place.isEmpty ? nil : place
        entry.latitude = draft.latitude
        entry.longitude = draft.longitude
        entry.mediaAssetIDs = draft.assetIDs
        entry.updatedAt = .now
        if let visit = draft.visit, !(entry.visits ?? []).contains(visit) {
            entry.visits = (entry.visits ?? []) + [visit]
        }
        if entry.publishStatus == .published {
            entry.publishStatus = .needsUpdate
        }
    }
}
