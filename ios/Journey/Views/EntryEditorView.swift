import PhotosUI
import SwiftData
import SwiftUI
import Translation

struct EntryDraft: Identifiable {
    let id = UUID()
    var entry: Entry?
    var title = ""
    var body = ""
    var date = Date.now
    var timeZoneIdentifier = TimeZone.current.identifier
    var placeName = ""
    var latitude: Double?
    var longitude: Double?
    var assetIDs: [String] = []
    var visit: Visit?
    var narrative = ""
    var narrativeSource: NarrativeSource = .user
    // The narrative as its source left it; any difference at save time means the user edited it.
    var sourcedNarrative = ""
    var translationLanguage = ""
    var translatedTitle = ""
    var translatedBody = ""
    var translatedNarrative = ""
    var tags: [Tag] = []

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
        timeZoneIdentifier = entry.timeZoneIdentifier
        placeName = entry.placeName ?? ""
        latitude = entry.latitude
        longitude = entry.longitude
        assetIDs = entry.mediaAssetIDs
        narrative = entry.narrative
        narrativeSource = entry.narrativeSource
        sourcedNarrative = entry.narrative
        translationLanguage = entry.translationLanguage
        translatedTitle = entry.translatedTitle
        translatedBody = entry.translatedBody
        translatedNarrative = entry.translatedNarrative
        tags = entry.tags ?? []
    }

    init(stop: DayTimeline.Stop) {
        visit = stop.visit
        date = stop.visit.arrival
        timeZoneIdentifier = stop.visit.timeZoneIdentifier
        placeName = stop.visit.placeName ?? ""
        latitude = stop.visit.latitude
        longitude = stop.visit.longitude
        assetIDs = stop.assetIDs
    }

    var originalTexts: EntryTranslator.Texts {
        EntryTranslator.Texts(title: title, body: body, narrative: narrative)
    }
}

struct EntryEditorView: View {
    private enum Field: Hashable {
        case title, place, notes, story
    }

    let journal: Journal
    @State private var draft: EntryDraft
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isPickingDayPhotos = false
    @State private var isDrafting = false
    @State private var draftError: String?
    @State private var saveError: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationTarget: String?
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var dictation = Dictation()
    @AppStorage("dictationLanguage") private var dictationLanguage = "en"
    @FocusState private var focusedField: Field?
    @Query(sort: \Tag.name) private var allTags: [Tag]
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
                        .focused($focusedField, equals: .title)
                    TextField("Place", text: $draft.placeName)
                        .focused($focusedField, equals: .place)
                    DatePicker("When", selection: $draft.date)
                }

                tagsSection

                Section("Notes") {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 160)
                        .focused($focusedField, equals: .notes)
                }

                mediaSection
                storySection
                translationSection
            }
            .navigationTitle(draft.entry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try save()
                            dismiss()
                        } catch {
                            saveError = "Your entry could not be saved. \(error.localizedDescription)"
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Menu {
                        Picker("Dictation Language", selection: $dictationLanguage) {
                            ForEach(EntryTranslator.languages, id: \.code) { language in
                                Text(language.name).tag(language.code)
                            }
                        }
                    } label: {
                        Text(dictationLanguage.uppercased())
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(dictation.isListening || dictation.isPreparing)
                    Text(dictationStatus)
                        .font(.footnote)
                        .foregroundStyle(dictation.errorMessage == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button(dictation.isListening ? "Stop Dictation" : "Dictate",
                           systemImage: dictation.isListening ? "stop.circle.fill" : "mic.fill",
                           action: toggleDictation)
                        .tint(dictation.isListening ? .red : .accentColor)
                        .disabled(focusedField == nil || dictation.isPreparing)
                }
            }
            .alert("Couldn’t Save Entry", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                let newIDs = items.compactMap(\.itemIdentifier).filter { !draft.assetIDs.contains($0) }
                draft.assetIDs.append(contentsOf: newIDs)
                pickerItems = []
            }
            .sheet(isPresented: $isPickingDayPhotos) {
                DayPhotoPicker(
                    day: draft.date,
                    timeZoneIdentifier: draft.timeZoneIdentifier,
                    selection: $draft.assetIDs
                )
            }
            .translationTask(translationConfig) { session in
                await translate(with: session)
            }
            .onDisappear {
                Task { await dictation.stop() }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            if allTags.isEmpty {
                Text("Create tags in Settings to label entries.")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout {
                    ForEach(allTags) { tag in
                        let isSelected = draft.tags.contains { $0.id == tag.id }
                        Button {
                            if isSelected {
                                draft.tags.removeAll { $0.id == tag.id }
                            } else {
                                draft.tags.append(tag)
                            }
                        } label: {
                            TagChip(tag: tag, isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var mediaSection: some View {
        Section("Photos & videos") {
            if !draft.assetIDs.isEmpty {
                AssetGrid(
                    ids: draft.assetIDs,
                    onRemove: { id in draft.assetIDs.removeAll { $0 == id } },
                    onReorder: { draft.assetIDs = $0 }
                )
            }
            Button {
                isPickingDayPhotos = true
            } label: {
                Label("Add from \(draft.date.formatted(.dateTime.day().month()))", systemImage: "photo.badge.plus")
            }
            PhotosPicker(
                selection: $pickerItems,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Label("Browse All Photos", systemImage: "photo.on.rectangle.angled")
            }
        }
    }

    private var storySection: some View {
        Section {
            TextEditor(text: $draft.narrative)
                .frame(minHeight: 120)
                .disabled(isDrafting)
                .focused($focusedField, equals: .story)
            Button {
                Task { await draftNarrative() }
            } label: {
                if isDrafting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Drafting…")
                    }
                } else {
                    Label(draft.narrative.isEmpty ? "Draft with Apple Intelligence" : "Redraft with Apple Intelligence",
                          systemImage: "sparkles")
                }
            }
            .disabled(isDrafting || NarrativeDrafter.unavailableReason != nil)
        } header: {
            Text("Story")
        } footer: {
            if let reason = NarrativeDrafter.unavailableReason {
                Text(reason)
            } else if let draftError {
                Text(draftError).foregroundStyle(.red)
            } else {
                Text("Written on your iPhone from the place, the time, your notes and what's in your photos. Your notes are never changed.")
            }
        }
    }

    private var translationSection: some View {
        Section {
            if !draft.translationLanguage.isEmpty {
                TextField("Title", text: $draft.translatedTitle)
                if !draft.body.isEmpty || !draft.translatedBody.isEmpty {
                    translatedEditor("Notes", text: $draft.translatedBody)
                }
                if !draft.narrative.isEmpty || !draft.translatedNarrative.isEmpty {
                    translatedEditor("Story", text: $draft.translatedNarrative)
                }
            }
            Menu {
                ForEach(EntryTranslator.languages, id: \.code) { language in
                    Button("To \(language.name)") { requestTranslation(to: language.code) }
                }
            } label: {
                if isTranslating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Translating…")
                    }
                } else {
                    Label(draft.translationLanguage.isEmpty ? "Translate" : "Translate Again", systemImage: "translate")
                }
            }
            .disabled(isTranslating)
        } header: {
            Text(draft.translationLanguage.isEmpty
                 ? "Translation"
                 : "Translation · \(EntryTranslator.name(for: draft.translationLanguage))")
        } footer: {
            if let translationError {
                Text(translationError).foregroundStyle(.red)
            } else {
                Text("Translated on your iPhone. What you wrote stays as it is.")
            }
        }
    }

    private func translatedEditor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: 80)
        }
    }

    private var dictationStatus: String {
        if let error = dictation.errorMessage { return error }
        if dictation.isPreparing { return "Getting ready…" }
        if dictation.isListening { return dictation.partialText.isEmpty ? "Listening…" : dictation.partialText }
        return ""
    }

    private func toggleDictation() {
        if dictation.isListening {
            Task { await dictation.stop() }
            return
        }
        guard let field = focusedField else { return }
        Task {
            await dictation.start(language: dictationLanguage) { text in
                append(text, to: focusedField ?? field)
            }
        }
    }

    private func append(_ text: String, to field: Field) {
        let piece = text.trimmingCharacters(in: .whitespaces)
        guard !piece.isEmpty else { return }
        func joined(_ existing: String) -> String {
            guard !existing.isEmpty else { return piece }
            let separator = existing.hasSuffix(" ") || existing.hasSuffix("\n") ? "" : " "
            return existing + separator + piece
        }
        switch field {
        case .title: draft.title = joined(draft.title)
        case .place: draft.placeName = joined(draft.placeName)
        case .notes: draft.body = joined(draft.body)
        case .story: draft.narrative = joined(draft.narrative)
        }
    }

    private func requestTranslation(to code: String) {
        translationError = nil
        let texts = draft.originalTexts
        guard !texts.isEmpty else {
            translationError = "Write something to translate first."
            return
        }
        if EntryTranslator.detectLanguage(of: texts) == code {
            translationError = "This entry is already in \(EntryTranslator.name(for: code))."
            return
        }
        // Re-running the same configuration needs invalidate(); a new target starts a new session.
        if translationConfig != nil, translationTarget == code {
            translationConfig?.invalidate()
        } else {
            translationTarget = code
            translationConfig = TranslationSession.Configuration(target: Locale.Language(identifier: code))
        }
    }

    private func translate(with session: TranslationSession) async {
        guard let code = translationTarget else { return }
        isTranslating = true
        defer { isTranslating = false }
        do {
            let result = try await EntryTranslator.translate(draft.originalTexts, with: session)
            draft.translationLanguage = code
            draft.translatedTitle = result.title
            draft.translatedBody = result.body
            draft.translatedNarrative = result.narrative
        } catch {
            translationError = error.localizedDescription
        }
    }

    private func draftNarrative() async {
        isDrafting = true
        draftError = nil
        defer { isDrafting = false }
        let labels = await PhotoLabeler.labels(for: draft.assetIDs)
        let context = NarrativeDrafter.Context(
            title: draft.title,
            place: draft.placeName,
            date: draft.date,
            notes: draft.body,
            photoLabels: labels,
            mediaCount: draft.assetIDs.count
        )
        do {
            try await NarrativeDrafter.draft(context) { draft.narrative = $0 }
            draft.narrativeSource = .onDevice
            draft.sourcedNarrative = draft.narrative
        } catch {
            draftError = NarrativeDrafter.message(for: error)
        }
    }

    private func save() throws {
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
        entry.narrative = draft.narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.narrativeSource = draft.narrative == draft.sourcedNarrative ? draft.narrativeSource : .user
        entry.translationLanguage = draft.translationLanguage
        entry.translatedTitle = draft.translatedTitle
        entry.translatedBody = draft.translatedBody
        entry.translatedNarrative = draft.translatedNarrative
        entry.tags = draft.tags
        entry.updatedAt = .now
        let fallbackTimeZone = draft.visit.map {
            LocalDay.timeZone(identifier: $0.timeZoneIdentifier)
        } ?? LocalDay.timeZone(identifier: entry.timeZoneIdentifier)
        LocalDay.capture(entry, timeZone: fallbackTimeZone)
        if let visit = draft.visit, !(entry.visits ?? []).contains(visit) {
            entry.visits = (entry.visits ?? []) + [visit]
        }
        if entry.publishStatus == .published {
            entry.publishStatus = .needsUpdate
        }
        try context.save()
        if let latitude = entry.latitude, let longitude = entry.longitude {
            let cache = try EntryMetadataCache.findOrCreate(for: entry.id, in: context)
            Task {
                await PlaceNamer.refresh(entry: entry, cache: cache) { requestedLatitude, requestedLongitude in
                    guard requestedLatitude == latitude, requestedLongitude == longitude else { return nil }
                    return await PlaceNamer.coordinateDetails(
                        latitude: requestedLatitude,
                        longitude: requestedLongitude
                    )
                }
                do {
                    try context.save()
                } catch {
                    saveError = "The updated location details could not be saved. \(error.localizedDescription)"
                }
            }
        }
    }
}
