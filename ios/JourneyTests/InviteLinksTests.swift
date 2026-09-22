import XCTest

@testable import Journey

final class InviteLinksTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let secrets = MemorySecrets()

    override func setUp() {
        super.setUp()
        suiteName = "links-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func remember(_ token: String, for id: UUID) {
        InviteLinks.remember(token: token, for: id, defaults: defaults, secrets: secrets)
    }

    private let website = URL(string: "https://ashone.me")!

    func testARememberedTokenBecomesAShareableLink() {
        let id = UUID()
        remember("tokentokentokentokentokentoken12", for: id)
        XCTAssertEqual(
            InviteLinks.url(for: id, website: website, secrets: secrets)?.absoluteString,
            "https://ashone.me/i/tokentokentokentokentokentoken12"
        )
    }

    /// The whole point: an invitation can be shared again without issuing a
    /// new link, so nobody's existing link breaks.
    func testSharingAgainDoesNotNeedANewToken() {
        let id = UUID()
        remember("abcabcabcabcabcabcabcabcabcabc12", for: id)
        let first = InviteLinks.url(for: id, website: website, secrets: secrets)
        let second = InviteLinks.url(for: id, website: website, secrets: secrets)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testAnUnknownInvitationHasNoLink() {
        XCTAssertNil(InviteLinks.url(for: UUID(), website: website, secrets: secrets))
    }

    /// Only the token is kept, so a link survives the journal moving domain.
    func testTheLinkFollowsTheCurrentWebsite() {
        let id = UUID()
        remember("movemovemovemovemovemovemove1234", for: id)
        XCTAssertEqual(
            InviteLinks.url(for: id, website: URL(string: "https://elsewhere.example")!, secrets: secrets)?.absoluteString,
            "https://elsewhere.example/i/movemovemovemovemovemovemove1234"
        )
    }

    func testForgettingRemovesTheSecretAndTheIndexEntry() {
        let id = UUID()
        remember("forgetforgetforgetforgetforget12", for: id)
        XCTAssertEqual(InviteLinks.rememberedIDs(defaults: defaults), [id])
        InviteLinks.forget(id, defaults: defaults, secrets: secrets)
        XCTAssertNil(InviteLinks.token(for: id, secrets: secrets))
        XCTAssertEqual(InviteLinks.rememberedIDs(defaults: defaults), [])
    }

    /// Revoking an invitation should dispose of its secret, not just hide it.
    func testPruningForgetsInvitationsThatAreNoLongerUsable() {
        let kept = UUID()
        let revoked = UUID()
        remember("keepkeepkeepkeepkeepkeepkeep1234", for: kept)
        remember("dropdropdropdropdropdropdrop1234", for: revoked)

        InviteLinks.prune(keeping: [kept], defaults: defaults, secrets: secrets)

        XCTAssertNotNil(InviteLinks.token(for: kept, secrets: secrets))
        XCTAssertNil(InviteLinks.token(for: revoked, secrets: secrets), "a revoked invitation's token must not linger")
        XCTAssertEqual(InviteLinks.rememberedIDs(defaults: defaults), [kept])
    }

    func testAnEmptyTokenIsNotRemembered() {
        let id = UUID()
        remember("", for: id)
        XCTAssertNil(InviteLinks.token(for: id, secrets: secrets))
        XCTAssertEqual(InviteLinks.rememberedIDs(defaults: defaults), [])
    }
}

/// Stands in for the Keychain, which a test bundle cannot write to.
private final class MemorySecrets: InviteSecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func string(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    func set(_ value: String?, for account: String) {
        lock.withLock {
            if let value, !value.isEmpty { values[account] = value } else { values[account] = nil }
        }
    }
}
