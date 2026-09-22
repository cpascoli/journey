import XCTest

@testable import Journey

final class APIErrorTests: XCTestCase {
    private func error(status: Int, json: String) -> APIError {
        APIError(status: status, body: Data(json.utf8))
    }

    /// The website names the atoms it found. Dropping them left the user with
    /// "strip the video's metadata" and no way to tell what was actually in
    /// the file, which is the one detail that makes the message actionable.
    func testMediaRejectionNamesWhatTheWebsiteFound() {
        let rejected = error(status: 422, json: """
        {"error":{"code":"VALIDATION_ERROR","message":"Strip the video's metadata before uploading: it can carry the exact location.","field":"body","metadata":["quicktime-location","apple-location-key"]}}
        """)

        XCTAssertEqual(rejected.metadata, ["quicktime-location", "apple-location-key"])
        let description = try? XCTUnwrap(rejected.errorDescription)
        XCTAssertEqual(
            description,
            "Strip the video's metadata before uploading: it can carry the exact location. (quicktime-location, apple-location-key)"
        )
    }

    func testAnErrorWithoutMetadataReadsExactlyAsTheWebsiteWroteIt() {
        let plain = error(status: 404, json: """
        {"error":{"code":"UNKNOWN_ENTRY","message":"Save the entry before uploading its videos."}}
        """)

        XCTAssertEqual(plain.metadata, [])
        XCTAssertEqual(plain.errorDescription, "Save the entry before uploading its videos.")
    }

    /// Authentication failures keep their own guidance, which is more useful
    /// than whatever the server said.
    func testKeyProblemsExplainWhereToFixThem() {
        let unauthorized = error(status: 401, json: #"{"error":{"code":"UNAUTHENTICATED","message":"Authentication required."}}"#)
        XCTAssertEqual(unauthorized.errorDescription, "The website didn't accept the key. Check it in Settings → Website.")

        let forbidden = error(status: 403, json: #"{"error":{"code":"PERMISSION_DENIED","message":"This key cannot perform this operation."}}"#)
        XCTAssertEqual(forbidden.errorDescription, "This key isn't allowed to publish. Use the owner key.")
    }

    func testAnUnreadableBodyStillProducesSomethingSayable() {
        let broken = error(status: 502, json: "<html>gateway</html>")
        XCTAssertEqual(broken.code, "HTTP_502")
        XCTAssertEqual(broken.errorDescription, "The website answered with status 502.")
    }
}

final class CommentSummaryTests: XCTestCase {
    private func thread(
        name: String = "Family",
        count: Int = 3,
        unseen: Int = 0,
        revoked: Bool = false
    ) throws -> RemoteCommentThread {
        let json = """
        {"entry_id":"\(UUID().uuidString.lowercased())","entry_title":"A day",
         "entry_day":"2026-09-20","invite_id":"\(UUID().uuidString.lowercased())",
         "invite_name":"\(name)","invite_revoked":\(revoked),
         "comment_count":\(count),"unseen_count":\(unseen),"last_at":"2026-09-20T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RemoteCommentThread.self, from: Data(json.utf8))
    }

    func testNamesTheInvitationAndCountsTheComments() throws {
        XCTAssertEqual(CommentSummary.text(thread: try thread()), "Family · 3 comments")
    }

    func testCountsOneCommentInTheSingular() throws {
        XCTAssertEqual(CommentSummary.text(thread: try thread(count: 1)), "Family · 1 comment")
    }

    /// A revoked invitation can no longer read replies, so the row says so.
    func testShowsWhenTheInvitationIsRevoked() throws {
        XCTAssertEqual(
            CommentSummary.text(thread: try thread(count: 2, revoked: true)),
            "Family · 2 comments · revoked"
        )
    }

    /// Threads are keyed per invitation per entry, so two invitations
    /// commenting on one entry must not collapse into a single row.
    func testThreadsOnOneEntryHaveDistinctIdentities() throws {
        let first = try thread(name: "Alice")
        let second = try thread(name: "Bob")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testAuthorDecidesWhichSideAReplyIsShownOn() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let owner = try decoder.decode(RemoteComment.self, from: Data("""
        {"id":"\(UUID().uuidString.lowercased())","author":"owner","body":"Thanks!","created_at":"2026-09-20T10:00:00Z"}
        """.utf8))
        let reader = try decoder.decode(RemoteComment.self, from: Data("""
        {"id":"\(UUID().uuidString.lowercased())","author":"reader","body":"Lovely","created_at":"2026-09-20T10:00:00Z"}
        """.utf8))
        XCTAssertTrue(owner.isOwner)
        XCTAssertFalse(reader.isOwner)
    }
}
