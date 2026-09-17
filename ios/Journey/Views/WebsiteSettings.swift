import SwiftUI

/// Settings → Website: where entries are published, and the owner key that allows it.
struct WebsiteSection: View {
    @AppStorage(JourneyAPI.websiteKey) private var website = JourneyAPI.defaultWebsite
    @State private var hasKey = Keychain.string(for: JourneyAPI.keyAccount) != nil
    @State private var isEnteringKey = false
    @State private var keyText = ""
    @State private var isChecking = false
    @State private var check: Result<Int, Error>?

    private var isWebsiteValid: Bool { JourneyAPI.websiteURL(website) != nil }

    var body: some View {
        Section {
            TextField("Website", text: $website)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: website) { check = nil }
            if hasKey {
                LabeledContent("Owner Key", value: "Saved")
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            Keychain.set(nil, for: JourneyAPI.keyAccount)
                            hasKey = false
                            check = nil
                        }
                        Button("Replace", systemImage: "key") { enterKey() }
                            .tint(.orange)
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
        } else if case let .success(count)? = check {
            Text("Connected. The website has \(count == 1 ? "1 tag" : "\(count) tags").")
        } else if case let .failure(error)? = check {
            Text(error.localizedDescription).foregroundStyle(.red)
        } else {
            Text("Entries are published only when you choose to, from the globe button on a journal page. Swipe the key to replace or remove it.")
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
        hasKey = Keychain.set(key, for: JourneyAPI.keyAccount)
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
