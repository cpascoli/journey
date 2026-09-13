import Foundation
import SwiftData

@Model
final class Journal {
    var id: UUID = UUID()
    var name: String = ""
    var isDefault: Bool = false
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Entry.journal) var entries: [Entry]? = []

    init(name: String, isDefault: Bool = false) {
        self.name = name
        self.isDefault = isDefault
    }

    @discardableResult
    static func ensureDefault(in context: ModelContext) -> Journal {
        let descriptor = FetchDescriptor<Journal>(predicate: #Predicate { $0.isDefault == true })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let journal = Journal(name: "Main", isDefault: true)
        context.insert(journal)
        return journal
    }
}
