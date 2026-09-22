import Foundation

/// Invitation links this phone has issued, so one can be shared again.
///
/// The website stores only a hash of a token and can never show a link again,
/// so without this the only way to share an existing invitation was to issue a
/// new link and break the old one.
///
/// The token is the secret, so it lives in the Keychain, this device only —
/// never iCloud, never another phone. Which invitations have a remembered
/// token is not secret, so that index is in UserDefaults, which makes it
/// possible to forget the ones that no longer matter.
///
/// Only the token is kept, not the whole URL: the address can change, and a
/// remembered link should survive the journal moving to a new domain.
/// Where the tokens are kept. The Keychain in the app; a test bundle has no
/// entitlement for it, so tests substitute their own.
nonisolated protocol InviteSecretStore: Sendable {
    func string(for account: String) -> String?
    func set(_ value: String?, for account: String)
}

nonisolated struct KeychainSecrets: InviteSecretStore {
    func string(for account: String) -> String? { Keychain.string(for: account) }
    func set(_ value: String?, for account: String) { Keychain.set(value, for: account) }
}

nonisolated enum InviteLinks {
    private static let indexKey = "rememberedInviteIDs"

    private static func account(_ id: UUID) -> String {
        "invite-token-\(id.uuidString.lowercased())"
    }

    static func remember(
        token: String,
        for id: UUID,
        defaults: UserDefaults = .standard,
        secrets: InviteSecretStore = KeychainSecrets()
    ) {
        guard !token.isEmpty else { return }
        secrets.set(token, for: account(id))
        var ids = Set(rememberedIDs(defaults: defaults))
        ids.insert(id)
        defaults.set(ids.map { $0.uuidString }.sorted(), forKey: indexKey)
    }

    static func forget(
        _ id: UUID,
        defaults: UserDefaults = .standard,
        secrets: InviteSecretStore = KeychainSecrets()
    ) {
        secrets.set(nil, for: account(id))
        let ids = rememberedIDs(defaults: defaults).filter { $0 != id }
        defaults.set(ids.map { $0.uuidString }.sorted(), forKey: indexKey)
    }

    static func token(for id: UUID, secrets: InviteSecretStore = KeychainSecrets()) -> String? {
        secrets.string(for: account(id))
    }

    /// The link to share, built from the website the app currently publishes
    /// to, so it is right even after the journal changes address.
    static func url(
        for id: UUID,
        website: URL,
        secrets: InviteSecretStore = KeychainSecrets()
    ) -> URL? {
        guard let token = token(for: id, secrets: secrets) else { return nil }
        return website.appending(path: "i").appending(path: token)
    }

    static func rememberedIDs(defaults: UserDefaults = .standard) -> [UUID] {
        (defaults.stringArray(forKey: indexKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    /// Forgets tokens for invitations that no longer exist or can no longer be
    /// used, so revoking an invitation also disposes of its secret.
    static func prune(
        keeping usable: [UUID],
        defaults: UserDefaults = .standard,
        secrets: InviteSecretStore = KeychainSecrets()
    ) {
        let keep = Set(usable)
        for id in rememberedIDs(defaults: defaults) where !keep.contains(id) {
            forget(id, defaults: defaults, secrets: secrets)
        }
    }
}
