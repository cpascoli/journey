import Foundation

/// The website's owner API, which the app publishes through with the owner key.
/// The contract is `web/src/lib/api/owner-openapi.ts`: change both together.
struct JourneyAPI {
    static let defaultWebsite = "https://journey-web.netlify.app"
    /// UserDefaults key for the website address; the owner key itself lives in the Keychain.
    static let websiteKey = "websiteURL"
    static let keyAccount = "owner-api-key"

    let baseURL: URL
    let key: String

    /// The website and key saved in Settings, or nil when either is missing.
    static func configured() -> JourneyAPI? {
        let website = UserDefaults.standard.string(forKey: websiteKey) ?? defaultWebsite
        guard let url = websiteURL(website),
              let key = Keychain.string(for: keyAccount), !key.isEmpty else { return nil }
        return JourneyAPI(baseURL: url, key: key)
    }

    /// An https address, or nil: the key must never travel in the clear.
    static func websiteURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    // MARK: Endpoints

    /// Lists tags; used to check the website and key work.
    func tagCount() async throws -> Int {
        let data = try await send("GET", "api/v1/owner/tags")
        return try Self.decoder.decode(TagList.self, from: data).tags.count
    }

    func putTag(id: UUID, name: String, color: String) async throws {
        let body = try Self.encoder.encode(TagPayload(name: name, color: color))
        _ = try await send("PUT", "api/v1/owner/tags/\(id.uuidString.lowercased())", body: body, contentType: "application/json")
    }

    /// Saves the entry; returns the media keys the website doesn't have yet.
    func putEntry(id: UUID, _ payload: EntryPayload) async throws -> [String] {
        let body = try Self.encoder.encode(payload)
        let data = try await send("PUT", "api/v1/owner/entries/\(id.uuidString.lowercased())", body: body, contentType: "application/json")
        return try Self.decoder.decode(PutEntryResponse.self, from: data).missingMedia
    }

    /// Unpublishes the entry and deletes its photos from the website.
    func deleteEntry(id: UUID) async throws {
        _ = try await send("DELETE", "api/v1/owner/entries/\(id.uuidString.lowercased())")
    }

    func putPhoto(entryID: UUID, key mediaKey: String, _ photo: PhotoExport.Photo, takenAt: Date?, sortOrder: Int) async throws {
        var query = [
            URLQueryItem(name: "width", value: String(photo.width)),
            URLQueryItem(name: "height", value: String(photo.height)),
            URLQueryItem(name: "sort_order", value: String(sortOrder)),
        ]
        if let takenAt {
            // UTC with a Z: a "+hh:mm" offset would arrive as a space.
            query.append(URLQueryItem(name: "taken_at", value: takenAt.ISO8601Format()))
        }
        _ = try await send(
            "PUT", "api/v1/owner/entries/\(entryID.uuidString.lowercased())/media/\(mediaKey)",
            query: query, body: photo.jpeg, contentType: "image/jpeg"
        )
    }

    // MARK: Plumbing

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func send(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, contentType: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError(status: 0, code: "BAD_URL", message: "The website address isn't valid.") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, body: data) }
        return data
    }
}

nonisolated struct APIError: LocalizedError {
    let status: Int
    let code: String
    let message: String

    init(status: Int, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    /// Reads the website's `{ "error": { "code", "message" } }` body.
    init(status: Int, body: Data) {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        self.status = status
        code = envelope?.error.code ?? "HTTP_\(status)"
        message = envelope?.error.message ?? "The website answered with status \(status)."
    }

    var errorDescription: String? {
        switch status {
        case 401: "The website didn't accept the key. Check it in Settings → Website."
        case 403: "This key isn't allowed to publish. Use the owner key."
        default: message
        }
    }
}

/// The body of PUT /api/v1/owner/entries/{id}. Keys are sent in snake_case.
nonisolated struct EntryPayload: Encodable {
    nonisolated struct Location: Encodable {
        var placeName: String?
        /// The town or city; what's shown at city precision.
        var locality: String?
        var latitude: Double?
        var longitude: Double?
    }

    nonisolated struct Translation: Encodable {
        var language: String
        var title: String
        var notes: String
        var narrative: String
    }

    var journalName: String
    var occurredAt: String
    var day: String
    var title: String
    var notes: String
    var narrative: String
    var narrativeSource: String
    var location: Location?
    var locationPrecision: String
    var translation: Translation?
    var visibility: String
    var tagIds: [String]
    /// The entry's full, ordered photo set: photos not listed are deleted from the website.
    var mediaKeys: [String]
}

private nonisolated struct TagPayload: Encodable {
    var name: String
    var color: String
}

private nonisolated struct TagList: Decodable {
    nonisolated struct Item: Decodable { var id: String }
    var tags: [Item]
}

private nonisolated struct PutEntryResponse: Decodable {
    var missingMedia: [String]
}

private nonisolated struct ErrorEnvelope: Decodable {
    nonisolated struct Body: Decodable {
        var code: String
        var message: String
    }
    var error: Body
}
