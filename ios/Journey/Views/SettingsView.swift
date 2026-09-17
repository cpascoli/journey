import Photos
import SwiftData
import SwiftUI
import UIKit

private struct TagSheet: Identifiable {
    let id = UUID()
    let tag: Tag?
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    let journals: [Journal]
    let current: Journal
    @Binding var selectedID: String

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationService.self) private var location
    @AppStorage("dictationLanguage") private var dictationLanguage = "en"
    @AppStorage("appearance") private var appearance = AppearanceMode.system

    @State private var isAdding = false
    @State private var newName = ""
    @State private var renaming: Journal?
    @State private var renameText = ""
    @State private var deleting: Journal?
    @State private var journalOnWebsite: Journal?
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var tagSheet: TagSheet?
    @State private var tagInUse: Tag?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            journalsSection

            tagsSection

            WebsiteSection()

            Section("Dictation") {
                Picker("Language", selection: $dictationLanguage) {
                    ForEach(EntryTranslator.languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            }

            permissionsSection

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            }
        }
        .navigationTitle("Settings")
        .alert("New Journal", isPresented: $isAdding) {
            TextField("Name", text: $newName)
            Button("Create", action: createJournal)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Journal", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename", action: renameJournal)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Journal", role: .destructive, action: deleteJournal)
        } message: {
            Text("Its \(deleting.map(entryCount) ?? "entries") will be deleted too. Photos stay in your library.")
        }
        .alert(
            "“\(journalOnWebsite?.name ?? "")” Has Published Entries",
            isPresented: Binding(get: { journalOnWebsite != nil }, set: { if !$0 { journalOnWebsite = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unpublish them first. Deleting the journal now would leave them on your website.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            }
        }
        .sheet(item: $tagSheet) { sheet in
            TagEditorView(tag: sheet.tag, otherNames: tags.filter { $0.id != sheet.tag?.id }.map(\.name))
        }
        .alert(
            "“\(tagInUse?.name ?? "")” Is in Use",
            isPresented: Binding(get: { tagInUse != nil }, set: { if !$0 { tagInUse = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Remove it from its \(tagInUse.map(tagUsage) ?? "entries") first. Deleting it now would leave them untagged, and untagged entries are visible to everyone you share the journal with.")
        }
    }

    private var tagsSection: some View {
        Section {
            ForEach(tags) { tag in
                Button {
                    tagSheet = TagSheet(tag: tag)
                } label: {
                    HStack {
                        TagChip(tag: tag)
                        Spacer()
                        Text(tagUsage(tag))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleteTag(tag) }
                }
            }
            Button("New Tag", systemImage: "plus") {
                tagSheet = TagSheet(tag: nil)
            }
            if tags.isEmpty {
                Button("Add Suggested Tags", systemImage: "wand.and.stars", action: addSuggestedTags)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("When you share the journal, each invite can be limited to tags: an entry is shown only to invites that include all of its tags, and entries without tags are shown to everyone you invite.")
        }
    }

    private func tagUsage(_ tag: Tag) -> String {
        let count = tag.entries?.count ?? 0
        return count == 1 ? "1 entry" : "\(count) entries"
    }

    private func deleteTag(_ tag: Tag) {
        if (tag.entries?.count ?? 0) > 0 {
            tagInUse = tag
        } else {
            context.delete(tag)
        }
    }

    private func addSuggestedTags() {
        let suggestions: [(String, TagColor)] = [
            ("Family", .pink), ("Friends", .blue), ("Sport", .green), ("Clubbing", .purple), ("Dating", .red),
        ]
        for (name, color) in suggestions {
            context.insert(Tag(name: name, color: color))
        }
    }

    private var journalsSection: some View {
        Section {
            ForEach(journals) { journal in
                Button {
                    selectedID = journal.id.uuidString
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(journal.name)
                            Text(entryCount(journal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if journal.id == current.id {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if !journal.isDefault {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            // Its published entries would stay online.
                            if (journal.entries ?? []).contains(where: { $0.publishStatus != .notPublished }) {
                                journalOnWebsite = journal
                            } else {
                                deleting = journal
                            }
                        }
                    }
                    Button("Rename", systemImage: "pencil") {
                        renameText = journal.name
                        renaming = journal
                    }
                    .tint(.orange)
                }
            }
            Button("New Journal", systemImage: "plus") {
                newName = ""
                isAdding = true
            }
        } header: {
            Text("Journals")
        } footer: {
            Text("New entries, the day view and the calendar use the selected journal. Swipe a journal to rename or delete it.")
        }
    }

    private var permissionsSection: some View {
        Section {
            LabeledContent("Location", value: locationText)
            LabeledContent("Photos", value: photosText)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Places are recorded in the background when location is set to Always; Full Access lets Journey find each day's photos.")
        }
    }

    private var locationText: String {
        switch location.authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Not Asked"
        @unknown default: "Unknown"
        }
    }

    private var photosText: String {
        switch photoStatus {
        case .authorized: "Full Access"
        case .limited: "Limited"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Not Asked"
        @unknown default: "Unknown"
        }
    }

    private func entryCount(_ journal: Journal) -> String {
        let count = journal.entries?.count ?? 0
        return count == 1 ? "1 entry" : "\(count) entries"
    }

    private func createJournal() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let journal = Journal(name: name)
        context.insert(journal)
        selectedID = journal.id.uuidString
    }

    private func renameJournal() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            renaming?.name = name
        }
        renaming = nil
    }

    private func deleteJournal() {
        guard let journal = deleting, !journal.isDefault else { return }
        if journal.id == current.id {
            selectedID = journals.first { $0.isDefault }?.id.uuidString ?? ""
        }
        context.delete(journal)
        deleting = nil
    }
}
