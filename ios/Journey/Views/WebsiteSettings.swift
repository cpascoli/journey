import SwiftData
import SwiftUI

/// Settings → Website: where entries are published, and the owner key that allows it.
struct WebsiteSection: View {
    @State private var website = UserDefaults.standard.string(forKey: JourneyAPI.websiteKey) ?? JourneyAPI.defaultWebsite
    @State private var hasKey = Keychain.string(for: JourneyAPI.keyAccount) != nil
    @State private var isEnteringKey = false
    @State private var keyText = ""
    @State private var isChecking = false
    @State private var isMoving = false
    @State private var moveError: String?
    @State private var check: Result<Int, Error>?
    @Environment(Publisher.self) private var publisher
    @Query private var entries: [Entry]
    @Query private var operations: [PublishOperation]
    @Query private var destinations: [PublishDestination]

    private var isWebsiteValid: Bool { JourneyAPI.websiteURL(website) != nil }
    private var savedWebsite: String {
        UserDefaults.standard.string(forKey: JourneyAPI.websiteKey) ?? JourneyAPI.defaultWebsite
    }
    private var hasBindings: Bool {
        entries.contains { $0.publishDestinationID != nil } || !operations.isEmpty
    }
    private var bindingCount: Int {
        entries.filter { $0.publishDestinationID != nil }.count
    }
    private var legacyUnboundCount: Int {
        entries.filter { $0.publishStatus != .notPublished && $0.publishDestinationID == nil }.count
    }

    /// The address published work is actually bound to, which is not
    /// necessarily the one in the field: changing the app's default address
    /// re-points a install that never saved one explicitly.
    private var boundDestination: PublishDestination? {
        let boundIDs = Set(entries.compactMap(\.publishDestinationID) + operations.map(\.destinationID))
        return destinations.first { boundIDs.contains($0.id) }
    }

    /// True when published entries point at a different address from the one
    /// the app would now use. Until it is resolved the outbox cannot match a
    /// destination, so pending work waits without saying so.
    private var needsMove: Bool {
        guard let bound = boundDestination, let url = JourneyAPI.websiteURL(website) else { return false }
        return bound.baseURL != JourneyAPI(baseURL: url, key: "").destinationURL
    }

    var body: some View {
        Section {
            TextField("Website", text: $website)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: website) {
                    check = nil
                    moveError = nil
                }
                .disabled(hasBindings && !hasKey)
            if needsMove {
                // The same website under a new name: repoint published work
                // instead of demanding it all be unpublished first, which
                // would delete its photos and readers' comments.
                Button(isMoving ? "Moving…" : "Move Published Entries Here", action: moveWebsite)
                    .disabled(!isWebsiteValid || isMoving || !hasKey)
            } else if website != savedWebsite {
                Button("Save Website", action: saveWebsite)
                    .disabled(!isWebsiteValid || hasBindings)
            }
            if let moveError {
                Text(moveError).foregroundStyle(.red)
            }
            if hasKey {
                LabeledContent("Owner Key", value: "Saved")
                if !hasBindings {
                    HStack {
                        Button("Replace Key", systemImage: "key") { enterKey() }
                        Spacer()
                        Button("Remove Key", systemImage: "trash", role: .destructive) {
                            removeKey()
                        }
                    }
                }
            } else {
                Button("Add Owner Key", systemImage: "key", action: enterKey)
            }
            Button(action: checkConnection) {
                if isChecking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking…")
                    }
                } else {
                    Label("Check Connection", systemImage: "network")
                }
            }
            .disabled(!hasKey || !isWebsiteValid || isChecking)
        } header: {
            Text("Website")
        } footer: {
            footer
        }
        .alert("Owner Key", isPresented: $isEnteringKey) {
            SecureField("Key", text: $keyText)
            Button("Save", action: saveKey)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the owner secret from the website's JOURNEY_API_KEYS. It's kept in this iPhone's Keychain and only sent to your website.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !isWebsiteValid {
            Text("Use an https:// address.").foregroundStyle(.red)
        } else if needsMove, let bound = boundDestination {
            // Say it plainly: until this is resolved the outbox cannot match a
            // destination, so publishing waits and nothing else explains why.
            Text("\(bindingCount == 1 ? "1 published entry is" : "\(bindingCount) published entries are") still connected to \(bound.baseURL). Journey can't publish or update until they point here. Moving them keeps everything online — their photos and readers' comments stay exactly as they are.")
        } else if hasBindings {
            Text("This destination is locked while \(bindingCount == 1 ? "1 entry is" : "\(bindingCount) entries are") published or publishing. \(hasKey ? "Unpublish them and let pending removals finish before replacing the website or owner key." : "Restore the original owner key so Journey can finish or unpublish them.")")
        } else if legacyUnboundCount > 0 {
            Text("\(legacyUnboundCount == 1 ? "One older published entry has" : "\(legacyUnboundCount) older published entries have") not been matched to a website yet. You can correct the website or key; Journey will bind only entries that this owner key can read.")
        } else if case let .success(count)? = check {
            Text("Connected. The website has \(count == 1 ? "1 tag" : "\(count) tags").")
        } else if case let .failure(error)? = check {
            Text(error.localizedDescription).foregroundStyle(.red)
        } else {
            Text("Entries are published only when you choose to, from the globe button on a journal page.")
        }
    }

    private func enterKey() {
        keyText = ""
        isEnteringKey = true
    }

    private func saveKey() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        keyText = ""
        guard key.count >= 24 else {
            check = .failure(APIError(status: 0, code: "SHORT_KEY", message: "That key is too short: keys are at least 24 characters."))
            return
        }
        guard !hasBindings || !hasKey else {
            check = .failure(PublishingError.differentDestination)
            return
        }
        if hasBindings, let destination = destinations.first {
            guard let url = JourneyAPI.websiteURL(savedWebsite) else { return }
            let candidate = JourneyAPI(baseURL: url, key: key)
            guard candidate.destinationURL == destination.baseURL,
                  candidate.keyFingerprint == destination.keyFingerprint else {
                check = .failure(APIError(
                    status: 0,
                    code: "WRONG_DESTINATION_KEY",
                    message: "That is not the original owner key for the website with pending publications."
                ))
                return
            }
        }
        hasKey = Keychain.set(key, for: JourneyAPI.keyAccount)
        if !hasKey {
            check = .failure(APIError(status: 0, code: "KEYCHAIN_SAVE", message: "The owner key could not be saved. Try again."))
        } else {
            check = nil
        }
    }

    private func removeKey() {
        guard !hasBindings else { return }
        if Keychain.set(nil, for: JourneyAPI.keyAccount) {
            hasKey = false
            check = nil
        } else {
            check = .failure(APIError(status: 0, code: "KEYCHAIN_REMOVE", message: "The owner key could not be removed. Try again."))
        }
    }

    /// Repoints published work at the same website under its new address.
    private func moveWebsite() {
        guard let url = JourneyAPI.websiteURL(website),
              let key = Keychain.string(for: JourneyAPI.keyAccount) else { return }
        isMoving = true
        moveError = nil
        Task {
            do {
                try await publisher.moveDestination(to: JourneyAPI(baseURL: url, key: key))
                UserDefaults.standard.set(website, forKey: JourneyAPI.websiteKey)
                check = nil
            } catch {
                moveError = error.localizedDescription
            }
            isMoving = false
        }
    }

    private func saveWebsite() {
        guard !hasBindings, let url = JourneyAPI.websiteURL(website) else { return }
        website = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(website, forKey: JourneyAPI.websiteKey)
        check = nil
    }

    private func checkConnection() {
        guard let api = JourneyAPI.configured() else { return }
        isChecking = true
        Task {
            do {
                check = .success(try await api.tagCount())
            } catch {
                check = .failure(error)
            }
            isChecking = false
        }
    }
}
