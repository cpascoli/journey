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

final class ThumbnailContractTests: XCTestCase {
    /// The app must not export a thumbnail the website will refuse for size.
    func testThumbnailLimitsMatchTheWebsiteContract() {
        XCTAssertEqual(PhotoExport.maxThumbnailBytes, 400 * 1024, "web MAX_THUMBNAIL_BYTES")
        XCTAssertLessThan(PhotoExport.thumbnailPixelSize, PhotoExport.maxPixelSize)
    }

    /// The point of the whole thing: a grid item should cost a fraction of
    /// the full image, so the size caps have to differ by an order of
    /// magnitude rather than a little.
    func testAThumbnailIsMuchSmallerThanAPhoto() {
        XCTAssertLessThan(PhotoExport.maxThumbnailBytes * 10, PhotoExport.maxBytes)
    }

    /// The website reports which keys still lack a small copy; anything it
    /// does not mark as having one must be offered a thumbnail.
    func testMediaWithoutAThumbnailIsReported() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = """
        {"entry":{"client_content_hash":null,"media":[
          {"asset_key":"has","thumb":true},
          {"asset_key":"missing","thumb":false},
          {"asset_key":"older"}
        ]}}
        """
        let state = try decoder.decode(GetEntryResponse.self, from: Data(json.utf8)).entry.state
        XCTAssertEqual(state.mediaKeys, ["has", "missing", "older"])
        // An entry published before thumbnails existed sends no flag at all,
        // and must still be treated as missing one.
        XCTAssertEqual(state.keysWithoutThumbnail, ["missing", "older"])
    }
}

final class AssetRowLengthTests: XCTestCase {
    func testWritesAClipLengthTheUsualWay() {
        XCTAssertEqual(AssetRow.length(0), "0:00")
        XCTAssertEqual(AssetRow.length(9), "0:09")
        XCTAssertEqual(AssetRow.length(65), "1:05")
        XCTAssertEqual(AssetRow.length(600), "10:00")
    }

    func testRoundsToTheNearestSecondRatherThanTruncating() {
        XCTAssertEqual(AssetRow.length(59.6), "1:00")
        XCTAssertEqual(AssetRow.length(89.4), "1:29")
    }

    /// A duration should never read as negative, whatever Photos reports.
    func testNeverShowsANegativeLength() {
        XCTAssertEqual(AssetRow.length(-5), "0:00")
    }

    /// The row warns using the same limit the export enforces, so what it
    /// says and what happens cannot drift apart.
    func testTheWarningThresholdIsTheExportLimit() {
        XCTAssertEqual(VideoExport.maxDuration, 90)
        XCTAssertEqual(AssetRow.length(VideoExport.maxDuration), "1:30")
    }
}
