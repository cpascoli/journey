import Foundation
import NaturalLanguage
import Translation

/// Translates an entry between English and Italian with Apple's on-device Translation framework.
enum EntryTranslator {
    static let languages: [(code: String, name: String)] = [("en", "English"), ("it", "Italian")]

    struct Texts {
        var title = ""
        var body = ""
        var narrative = ""

        var isEmpty: Bool {
            [title, body, narrative].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    static func name(for code: String) -> String {
        languages.first { $0.code == code }?.name ?? code
    }

    static func detectLanguage(of texts: Texts) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: [texts.title, texts.body, texts.narrative].joined(separator: "\n"))?.rawValue
    }

    static func translate(_ texts: Texts, with session: TranslationSession) async throws -> Texts {
        let fields = [("title", texts.title), ("body", texts.body), ("narrative", texts.narrative)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let requests = fields.map { TranslationSession.Request(sourceText: $0.1, clientIdentifier: $0.0) }
        var result = Texts()
        for response in try await session.translations(from: requests) {
            switch response.clientIdentifier {
            case "title": result.title = response.targetText
            case "body": result.body = response.targetText
            case "narrative": result.narrative = response.targetText
            default: break
            }
        }
        return result
    }
}
