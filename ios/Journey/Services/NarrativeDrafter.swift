import Foundation
import FoundationModels

/// Drafts an entry's narrative with Apple's on-device language model.
enum NarrativeDrafter {
    struct Context {
        var title: String
        var place: String
        var date: Date
        var notes: String
        var photoLabels: [String]
        var mediaCount: Int
    }

    /// Why drafting isn't possible right now, or nil when the model is ready.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings to draft stories."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still getting ready. Try again in a little while."
        case .unavailable:
            "Apple Intelligence isn't available right now."
        }
    }

    private static let instructions = """
        You write short travel journal entries in the first person, as the traveller.
        Use only the facts you are given. Never invent names, people, food, weather or events.
        Write two to four plain, warm sentences. No title, hashtags or emojis.
        """

    /// Streams the draft, calling `onUpdate` with the full text so far.
    static func draft(_ context: Context, onUpdate: (String) -> Void) async throws {
        let session = LanguageModelSession(instructions: instructions)
        for try await snapshot in session.streamResponse(to: prompt(for: context)) {
            onUpdate(snapshot.content)
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return error.localizedDescription
        }
        switch error {
        case .guardrailViolation:
            return "Apple Intelligence declined to write about this entry."
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence doesn't support this language yet."
        case .exceededContextWindowSize:
            return "There's too much here to draft from. Try shorter notes."
        default:
            return error.localizedDescription
        }
    }

    private static func prompt(for context: Context) -> String {
        var lines = ["Write the journal entry for this moment."]
        lines.append("When: \(context.date.formatted(date: .complete, time: .shortened))")
        if !context.place.isEmpty {
            lines.append("Where: \(context.place)")
        }
        if !context.title.isEmpty {
            lines.append("Title: \(context.title)")
        }
        if !context.notes.isEmpty {
            lines.append("My notes: \(context.notes)")
        }
        if context.mediaCount > 0 {
            let what = context.photoLabels.isEmpty ? "" : ", showing: \(context.photoLabels.joined(separator: ", "))"
            lines.append("I took \(context.mediaCount) photos and videos\(what).")
        }
        return lines.joined(separator: "\n")
    }
}
