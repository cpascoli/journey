import Foundation
import Observation

/// How many reader comments are waiting, for the Sharing tab's badge.
///
/// Refreshed when the app comes to the foreground rather than on a timer:
/// a journal's comments arrive over days, so polling would spend battery to
/// learn nothing. The last count is remembered, so the badge is right at
/// launch and stays honest offline instead of dropping to zero.
@Observable
final class CommentInbox {
    private static let storageKey = "unseenCommentCount"

    private(set) var unseenCount: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unseenCount = defaults.integer(forKey: Self.storageKey)
    }

    func refresh() async {
        await refresh(using: JourneyAPI.configured())
    }

    /// Reads the count from the website. Failures leave the badge as it was:
    /// a badge must never interrupt, and being offline is not news. With no
    /// website configured there is nothing to be waiting, so it clears.
    func refresh(using api: JourneyAPI?) async {
        guard let api else {
            set(0)
            return
        }
        guard let count = try? await api.unseenCommentCount() else { return }
        set(count)
    }

    /// Called when a thread is read, so the badge drops without a round trip.
    func note(unseenCount count: Int) {
        set(max(0, count))
    }

    private func set(_ count: Int) {
        unseenCount = count
        defaults.set(count, forKey: Self.storageKey)
    }
}
