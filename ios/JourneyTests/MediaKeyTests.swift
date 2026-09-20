import XCTest

@testable import Journey

final class MediaKeyTests: XCTestCase {
    /// The key is how the website addresses already-published media. If this
    /// hash ever changes, every published photo becomes an orphan on the
    /// website and is re-uploaded under a new key, so it is pinned here.
    func testKeyIsTheSHA256OfThePhotosIdentifier() {
        XCTAssertEqual(
            MediaKey.key(for: "B84E8479-475C-4727-A4A4-B77AA9980897/L0/001"),
            "25ac900b60bf163ab51beee00a89dc049b1b6fdf5819c22b1437151cf535165d"
        )
    }

    /// Photos and videos share one key space: an entry's media_keys is a
    /// single ordered list, and PhotoExport must not diverge from MediaKey.
    func testPhotoAndVideoExportAgreeOnTheKey() {
        let identifier = "B84E8479-475C-4727-A4A4-B77AA9980897/L0/001"
        XCTAssertEqual(PhotoExport.key(for: identifier), MediaKey.key(for: identifier))
        XCTAssertEqual(VideoExport.key(for: identifier), MediaKey.key(for: identifier))
    }

    func testKeyContainsNoPathCharacters() {
        // The website's MEDIA_KEY_PATTERN is ^[A-Za-z0-9_-]{1,128}$.
        let key = MediaKey.key(for: "anything/with/slashes")
        XCTAssertNil(key.rangeOfCharacter(from: CharacterSet(charactersIn: "/+=")))
        XCTAssertEqual(key.count, 64)
    }

    /// The app must not export a clip the website will refuse for size.
    func testExportLimitsMatchTheWebsiteContract() {
        XCTAssertEqual(VideoExport.maxBytes, 60 * 1024 * 1024, "web MAX_VIDEO_BYTES")
        // 720p runs at roughly 4 Mbps, so the duration cap must keep a clip
        // comfortably inside the byte cap before any export work happens.
        let worstCaseBytes = VideoExport.maxDuration * 4_000_000 / 8
        XCTAssertLessThan(worstCaseBytes, Double(VideoExport.maxBytes))
    }
}

final class InviteAccessLabelTests: XCTestCase {
    func testNamesTheTagsAnInvitationMayRead() {
        let family = UUID()
        let sport = UUID()
        XCTAssertEqual(
            InviteAccessLabel.text(tagIDs: [family, sport], namesByID: [family: "Family", sport: "Sport"]),
            "Family, Sport"
        )
    }

    /// No tags is the widest setting, not the narrowest: an untagged entry is
    /// visible to every invitation, so the label must not read as "nothing".
    func testNoTagsMeansUntaggedEntries() {
        XCTAssertEqual(InviteAccessLabel.text(tagIDs: [], namesByID: [:]), "Untagged entries")
    }

    func testTagsThisPhoneDoesNotKnowAreStillCounted() {
        let known = UUID()
        XCTAssertEqual(
            InviteAccessLabel.text(tagIDs: [known, UUID(), UUID()], namesByID: [known: "Family"]),
            "Family, 2 unknown tags"
        )
    }

    func testReadsTextComesFromTheWebsiteAndHandlesRevocation() {
        XCTAssertEqual(InviteAccessLabel.readsText(visibleEntryCount: 12, isRevoked: false), "reads 12 entries")
        XCTAssertEqual(InviteAccessLabel.readsText(visibleEntryCount: 1, isRevoked: false), "reads 1 entry")
        XCTAssertEqual(InviteAccessLabel.readsText(visibleEntryCount: 0, isRevoked: false), "reads 0 entries")
        // A revoked invitation reads nothing whatever its tags say.
        XCTAssertEqual(InviteAccessLabel.readsText(visibleEntryCount: 12, isRevoked: true), "reads nothing")
        // Never claim access is zero when the count simply didn't arrive.
        XCTAssertEqual(InviteAccessLabel.readsText(visibleEntryCount: nil, isRevoked: false), "reads unknown")
    }
}
