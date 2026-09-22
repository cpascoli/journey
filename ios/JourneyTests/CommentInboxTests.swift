import XCTest

@testable import Journey

final class CommentInboxTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "inbox-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func api(status: Int, body: String) -> JourneyAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InboxURLProtocol.self]
        InboxURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        return JourneyAPI(
            baseURL: URL(string: "https://ashone.example")!,
            key: String(repeating: "k", count: 32),
            session: URLSession(configuration: configuration)
        )
    }

    func testReadsTheWaitingCountFromTheWebsite() async {
        let inbox = CommentInbox(defaults: defaults)
        await inbox.refresh(using: api(status: 200, body: #"{"threads":[],"unseen_total":4}"#))
        XCTAssertEqual(inbox.unseenCount, 4)
    }

    /// A badge must not lie about there being nothing waiting just because
    /// the phone is offline.
    func testAFailedRefreshKeepsTheLastKnownCount() async {
        let inbox = CommentInbox(defaults: defaults)
        await inbox.refresh(using: api(status: 200, body: #"{"threads":[],"unseen_total":3}"#))
        await inbox.refresh(using: api(status: 500, body: "nope"))
        XCTAssertEqual(inbox.unseenCount, 3)
    }

    func testNoWebsiteMeansNothingIsWaiting() async {
        let inbox = CommentInbox(defaults: defaults)
        await inbox.refresh(using: api(status: 200, body: #"{"threads":[],"unseen_total":2}"#))
        await inbox.refresh(using: nil)
        XCTAssertEqual(inbox.unseenCount, 0)
    }

    /// The badge is right the moment the app opens, before any request.
    func testTheCountSurvivesRelaunch() async {
        let first = CommentInbox(defaults: defaults)
        await first.refresh(using: api(status: 200, body: #"{"threads":[],"unseen_total":7}"#))
        XCTAssertEqual(CommentInbox(defaults: defaults).unseenCount, 7)
    }

    func testReadingAThreadDropsTheBadgeWithoutARequest() {
        let inbox = CommentInbox(defaults: defaults)
        inbox.note(unseenCount: 5)
        XCTAssertEqual(inbox.unseenCount, 5)
        inbox.note(unseenCount: 0)
        XCTAssertEqual(inbox.unseenCount, 0)
    }

    func testANegativeCountIsNeverShown() {
        let inbox = CommentInbox(defaults: defaults)
        inbox.note(unseenCount: -3)
        XCTAssertEqual(inbox.unseenCount, 0)
    }
}

private final class InboxURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
