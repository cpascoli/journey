import Foundation
import SwiftData

/// A label for entries, shared by all journals. Tags also decide who can see an
/// entry once the journal is shared: an invite sees an entry only if it includes
/// all of the entry's tags, and untagged entries are seen by every invite.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorName: String = TagColor.blue.rawValue
    var createdAt: Date = Date.now
    var entries: [Entry]? = []

    init(name: String, color: TagColor) {
        self.name = name
        self.colorName = color.rawValue
    }

    var color: TagColor {
        get { TagColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }
}

nonisolated enum TagColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    var id: Self { self }
}
