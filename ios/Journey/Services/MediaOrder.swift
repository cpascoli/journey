import Foundation

/// The order of an entry's photos and videos.
///
/// The order is the entry's `mediaAssetIDs`, and the website derives each
/// item's `sort_order` from its position in the `media_keys` it is sent — so
/// reordering here is republished without re-uploading anything.
nonisolated enum MediaOrder {
    /// Moves `id` so that it sits immediately before `target`.
    ///
    /// Anything unknown, or a move onto itself, leaves the order alone: a
    /// dropped item should never be able to lose its place.
    static func moving(_ id: String, before target: String, in ids: [String]) -> [String] {
        guard id != target, ids.contains(id), ids.contains(target) else { return ids }
        var result = ids
        result.removeAll { $0 == id }
        guard let insertion = result.firstIndex(of: target) else { return ids }
        result.insert(id, at: insertion)
        return result
    }

    /// Moves `id` to the end. Dropping only ever inserts *before* something,
    /// so without this there is no single move that makes an item last.
    static func movingToEnd(_ id: String, in ids: [String]) -> [String] {
        guard ids.contains(id), ids.last != id else { return ids }
        var result = ids
        result.removeAll { $0 == id }
        result.append(id)
        return result
    }
}
