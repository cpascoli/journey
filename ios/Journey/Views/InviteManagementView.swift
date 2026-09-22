import SwiftData
import SwiftUI

nonisolated enum InviteAccessLabel {
    static func text(tagIDs: [UUID], namesByID: [UUID: String]) -> String {
        guard !tagIDs.isEmpty else { return "Untagged entries" }
        let names = tagIDs.compactMap { namesByID[$0] }
        let unknownCount = tagIDs.count - names.count
        let unknown = unknownCount == 0
            ? []
            : ["\(unknownCount) unknown \(unknownCount == 1 ? "tag" : "tags")"]
        return (names + unknown).joined(separator: ", ")
    }

    /// What the invite can actually read. An invite sees an entry only when it
    /// carries every one of that entry's tags, which is easy to misjudge, so
    /// the count comes from the website rather than being guessed here.
    static func readsText(visibleEntryCount: Int?, isRevoked: Bool) -> String {
        if isRevoked { return "reads nothing" }
        guard let visibleEntryCount else { return "reads unknown" }
        return visibleEntryCount == 1 ? "reads 1 entry" : "reads \(visibleEntryCount) entries"
    }
}

struct InviteManagementView: View {
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var invites: [RemoteInvite] = []
    @State private var isLoading = false
    @State private var showingCreate = false
    @State private var errorMessage: String?
    @State private var shareURL: URL?

    var body: some View {
        List {
            if let shareURL {
                Section {
                    ShareLink(item: shareURL, subject: Text("Journey invitation")) {
                        Label("Share Invitation", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("New Invitation")
                } footer: {
                    Text("Share this link now. Journey does not save it and the website cannot show it again.")
                }
            }

            Section {
                if isLoading, invites.isEmpty {
                    ProgressView()
                } else if invites.isEmpty {
                    ContentUnavailableView("No Invitations", systemImage: "person.2")
                } else {
                    ForEach(invites) { invite in
                        NavigationLink {
                            InviteDetailView(invite: invite, tags: tags) { await reload() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(invite.name)
                                    Spacer()
                                    Text(invite.revokedAt == nil ? "Active" : "Revoked")
                                        .font(.caption)
                                        .foregroundStyle(invite.revokedAt == nil ? .green : .secondary)
                                }
                                Text(accessDescription(invite))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            if invite.revokedAt == nil {
                                Button("Revoke", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                                    revoke(invite)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("People")
            } footer: {
                Text("An invitation sees an entry only when it includes every tag on that entry. Untagged shared entries are visible to every active invitation.")
            }
        }
        .navigationTitle("Invitations")
        .toolbar {
            Button("New Invitation", systemImage: "plus") {
                shareURL = nil
                showingCreate = true
            }
            .disabled(JourneyAPI.configured() == nil)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showingCreate) {
            CreateInviteView(tags: tags) { name, tagIDs in
                try await create(name: name, tagIDs: tagIDs)
            }
        }
        .alert("Invitations", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func accessDescription(_ invite: RemoteInvite) -> String {
        let access = InviteAccessLabel.text(
            tagIDs: invite.tagIds,
            namesByID: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        )
        let reads = InviteAccessLabel.readsText(
            visibleEntryCount: invite.visibleEntryCount,
            isRevoked: invite.revokedAt != nil
        )
        let use = invite.lastSeenAt == nil ? "not opened" : "opened"
        return "\(access) · \(reads) · \(use)"
    }

    private func reload() async {
        guard let api = JourneyAPI.configured() else {
            errorMessage = "Add the website and owner key in Settings first."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            invites = try await api.invites()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create(name: String, tagIDs: Set<UUID>) async throws {
        guard let api = JourneyAPI.configured() else {
            throw APIError(status: 0, code: "NOT_CONFIGURED", message: "Add the website and owner key first.")
        }
        for tag in tags where tagIDs.contains(tag.id) {
            try await api.putTag(id: tag.id, name: tag.name, color: tag.color.rawValue)
        }
        let created = try await api.createInvite(name: name, tagIDs: Array(tagIDs))
        shareURL = created.url
        invites.insert(created.invite, at: 0)
    }

    private func revoke(_ invite: RemoteInvite) {
        Task {
            guard let api = JourneyAPI.configured() else { return }
            do {
                try await api.revokeInvite(id: invite.id)
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CreateInviteView: View {
    let tags: [Tag]
    let create: (String, Set<UUID>) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected = Set<UUID>()
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Person or group") {
                    TextField("Name", text: $name)
                }
                Section {
                    ForEach(tags) { tag in
                        Toggle(isOn: Binding(
                            get: { selected.contains(tag.id) },
                            set: { enabled in
                                if enabled { selected.insert(tag.id) } else { selected.remove(tag.id) }
                            }
                        )) {
                            TagChip(tag: tag)
                        }
                    }
                } header: {
                    Text("Allowed tags")
                } footer: {
                    Text("Select every tag this invitation may read.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Invitation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create") {
                        submit()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
    }

    private func submit() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await create(name.trimmingCharacters(in: .whitespacesAndNewlines), selected)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}


/// One invitation: what it may read, and its link.
///
/// Tags are saved as a whole set, because the website applies them in a single
/// statement — a partial change would briefly let the invitation read more than
/// intended. Nothing is saved until *Save* is tapped, so widening access is
/// always deliberate.
private struct InviteDetailView: View {
    let invite: RemoteInvite
    let tags: [Tag]
    let onChange: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>
    @State private var isSaving = false
    @State private var isReplacing = false
    @State private var replacedURL: URL?
    @State private var isConfirmingReplace = false
    @State private var errorMessage: String?

    init(invite: RemoteInvite, tags: [Tag], onChange: @escaping () async -> Void) {
        self.invite = invite
        self.tags = tags
        self.onChange = onChange
        _selected = State(initialValue: Set(invite.tagIds))
    }

    private var isRevoked: Bool { invite.revokedAt != nil }
    private var hasAPI: Bool { JourneyAPI.configured() != nil }
    private var hasChanges: Bool { selected != Set(invite.tagIds) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: isRevoked ? "Revoked" : "Active")
                LabeledContent(
                    "Reads",
                    value: InviteAccessLabel.readsText(
                        visibleEntryCount: invite.visibleEntryCount,
                        isRevoked: isRevoked
                    )
                )
            }

            // Always here, so sharing is never a thing you have to go and
            // find. Journey holds no link until one is made: the website
            // stores only a hash, so there is nothing to show again.
            Section {
                if let replacedURL {
                    ShareLink(item: replacedURL, subject: Text("Journey invitation")) {
                        Label("Share Invitation Link", systemImage: "square.and.arrow.up")
                    }
                } else if !isRevoked {
                    Button(isReplacing ? "Creating…" : "Create a Link to Share", systemImage: "link") {
                        isConfirmingReplace = true
                    }
                    .disabled(isReplacing || !hasAPI)
                }
            } header: {
                Text("Invitation Link")
            } footer: {
                if replacedURL != nil {
                    Text("Share this now. Journey does not save it and the website cannot show it again. Any previous link has stopped working.")
                } else if isRevoked {
                    Text("This invitation is revoked, so it has no link. Create a new invitation instead.")
                } else {
                    Text("Journey does not keep invitation links, and the website cannot show one again — it stores only a hash. Creating a link to share stops the current one working.")
                }
            }

            Section {
                ForEach(tags) { tag in
                    Toggle(isOn: Binding(
                        get: { selected.contains(tag.id) },
                        set: { enabled in
                            if enabled { selected.insert(tag.id) } else { selected.remove(tag.id) }
                        }
                    )) {
                        TagChip(tag: tag)
                    }
                }
                .disabled(isRevoked)
            } header: {
                Text("Allowed tags")
            } footer: {
                Text(selected.isEmpty
                    ? "With no tags, this invitation reads only entries that have no tags."
                    : "It reads an entry only when it has every one of that entry's tags.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(invite.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .disabled(!hasChanges || isSaving || isRevoked)
            }
        }
        .confirmationDialog(
            "Create a new link for this invitation?",
            isPresented: $isConfirmingReplace,
            titleVisibility: .visible
        ) {
            Button("Create New Link", role: .destructive) { replaceLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(invite.name) keeps their name and tags, but anyone holding the current link loses access immediately.")
        }
    }

    private func save() {
        guard let api = JourneyAPI.configured() else {
            errorMessage = "Add the website and owner key in Settings first."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                // Tags are referenced by id, so the website needs them before
                // it can accept them on an invitation.
                for tag in tags where selected.contains(tag.id) {
                    try await api.putTag(id: tag.id, name: tag.name, color: tag.color.rawValue)
                }
                _ = try await api.setInviteTags(id: invite.id, tagIDs: Array(selected))
                await onChange()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func replaceLink() {
        guard let api = JourneyAPI.configured() else {
            errorMessage = "Add the website and owner key in Settings first."
            return
        }
        isReplacing = true
        errorMessage = nil
        Task {
            do {
                replacedURL = try await api.replaceInviteLink(id: invite.id)
                await onChange()
            } catch {
                errorMessage = error.localizedDescription
            }
            isReplacing = false
        }
    }
}
