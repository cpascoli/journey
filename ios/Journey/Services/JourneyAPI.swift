import CryptoKit
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
    var session: URLSession = .shared

    var destinationURL: String {
        baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var keyFingerprint: String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

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

    /// Reads the server after a timeout or restart instead of guessing whether a write happened.
    func entryState(id: UUID) async throws -> RemoteEntryState? {
        do {
            let data = try await send("GET", "api/v1/owner/entries/\(id.uuidString.lowercased())")
            return try Self.decoder.decode(GetEntryResponse.self, from: data).entry.state
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    /// Unpublishes the entry and deletes its photos from the website.
    func deleteEntry(id: UUID) async throws {
        _ = try await send("DELETE", "api/v1/owner/entries/\(id.uuidString.lowercased())")
    }

    func invites() async throws -> [RemoteInvite] {
        let data = try await send("GET", "api/v1/owner/invites")
        return try Self.decoder.decode(InviteListResponse.self, from: data).invites
    }

    /// Creates an invite. Its link contains the one-time token and must not be persisted.
    func createInvite(name: String, tagIDs: [UUID]) async throws -> CreatedInvite {
        let body = try Self.encoder.encode(InvitePayload(name: name, tagIds: tagIDs.map { $0.uuidString.lowercased() }))
        let data = try await send("POST", "api/v1/owner/invites", body: body, contentType: "application/json")
        return try Self.decoder.decode(CreateInviteResponse.self, from: data).created
    }

    func revokeInvite(id: UUID) async throws {
        _ = try await send("DELETE", "api/v1/owner/invites/\(id.uuidString.lowercased())")
    }

    /// Replaces which tags an invite may read. The whole set is sent, because
    /// the website applies it in one statement: a partial change would briefly
    /// widen access.
    func setInviteTags(id: UUID, tagIDs: [UUID]) async throws -> [UUID] {
        let body = try Self.encoder.encode(InviteTagsPayload(tagIds: tagIDs.map { $0.uuidString.lowercased() }))
        let data = try await send(
            "PATCH", "api/v1/owner/invites/\(id.uuidString.lowercased())",
            body: body, contentType: "application/json"
        )
        return try Self.decoder.decode(SetInviteTagsResponse.self, from: data).invite.tagIds
    }

    /// Issues a new link and invalidates the old one. Like creation, the link
    /// comes back once and must not be persisted.
    func replaceInviteLink(id: UUID) async throws -> URL {
        let data = try await send("POST", "api/v1/owner/invites/\(id.uuidString.lowercased())/token")
        return try Self.decoder.decode(InviteLinkResponse.self, from: data).url
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

    /// Uploads a video in three steps, because a Netlify function's request
    /// body caps at 6 MB: ask the website for a signed URL, send the file
    /// straight to the object store, then have the website verify and record
    /// it. Only the third step makes the video part of the entry.
    func putVideo(
        entryID: UUID,
        key mediaKey: String,
        _ video: VideoExport.Video,
        takenAt: Date?,
        sortOrder: Int
    ) async throws {
        let path = "api/v1/owner/entries/\(entryID.uuidString.lowercased())/media/\(mediaKey)"
        let started = try Self.decoder.decode(
            StartUploadResponse.self,
            from: try await send("POST", "\(path)/upload-url")
        ).upload

        try await uploadFile(video.fileURL, to: started.url, contentType: started.contentType)

        var query = [URLQueryItem(name: "sort_order", value: String(sortOrder))]
        if let takenAt {
            // UTC with a Z: a "+hh:mm" offset would arrive as a space.
            query.append(URLQueryItem(name: "taken_at", value: takenAt.ISO8601Format()))
        }
        let body = try Self.encoder.encode(CommitVideoPayload(storagePath: started.storagePath))
        _ = try await send(
            "PUT", "\(path)/commit", query: query, body: body, contentType: "application/json"
        )
    }

    /// Streams the file from disk rather than loading it into memory, and goes
    /// to the object store directly, so it carries no owner key.
    private func uploadFile(_ fileURL: URL, to urlString: String, contentType: String) async throws {
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw APIError(status: 0, code: "BAD_UPLOAD_URL", message: "The website returned an upload address that isn't valid.")
        }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "PUT"
        // Signed into the URL: anything else is refused by the store.
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(
                status: status,
                code: "UPLOAD_FAILED",
                message: "The video couldn't be uploaded (status \(status))."
            )
        }
        _ = data
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
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, body: data) }
        return data
    }
}

nonisolated struct APIError: LocalizedError {
    let status: Int
    let code: String
    let message: String
    /// What the website found, when it rejected media for carrying metadata.
    /// Without this the app reports "strip the metadata" and discards the only
    /// clue about which atom or segment was actually found.
    let metadata: [String]

    init(status: Int, code: String, message: String, metadata: [String] = []) {
        self.status = status
        self.code = code
        self.message = message
        self.metadata = metadata
    }

    /// Reads the website's `{ "error": { "code", "message", "metadata" } }` body.
    init(status: Int, body: Data) {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        self.status = status
        code = envelope?.error.code ?? "HTTP_\(status)"
        message = envelope?.error.message ?? "The website answered with status \(status)."
        metadata = envelope?.error.metadata ?? []
    }

    var errorDescription: String? {
        switch status {
        case 401: "The website didn't accept the key. Check it in Settings → Website."
        case 403: "This key isn't allowed to publish. Use the owner key."
        default: metadata.isEmpty ? message : "\(message) (\(metadata.joined(separator: ", ")))"
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
    /// SHA-256 of the canonical payload with this field omitted.
    var clientContentHash: String? = nil

    func addingContentHash() throws -> EntryPayload {
        var payload = self
        payload.clientContentHash = nil
        let data = try Self.canonicalEncoder.encode(payload)
        payload.clientContentHash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return payload
    }

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private nonisolated struct StartUploadResponse: Decodable {
    nonisolated struct Upload: Decodable {
        var url: String
        var storagePath: String
        var contentType: String
        var maxBytes: Int
    }

    var upload: Upload
}

private nonisolated struct CommitVideoPayload: Encodable {
    var storagePath: String
}

private nonisolated struct TagPayload: Encodable {
    var name: String
    var color: String
}

private nonisolated struct TagList: Decodable {
    nonisolated struct Item: Decodable { var id: String }
    var tags: [Item]
}

nonisolated struct RemoteInvite: Decodable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let tagIds: [UUID]
    let createdAt: String
    let revokedAt: String?
    let lastSeenAt: String?
    /// How many entries this invite can actually read. The all-tags rule is
    /// easy to get wrong in the direction of sharing too much, so it's shown.
    let visibleEntryCount: Int?
}

nonisolated struct CreatedInvite: Decodable, Sendable {
    let invite: RemoteInvite
    let url: URL
}

private nonisolated struct InviteTagsPayload: Encodable {
    let tagIds: [String]
}

private nonisolated struct SetInviteTagsResponse: Decodable {
    nonisolated struct Invite: Decodable { let tagIds: [UUID] }
    let invite: Invite
}

private nonisolated struct InviteLinkResponse: Decodable {
    let url: URL
}

private nonisolated struct InvitePayload: Encodable {
    let name: String
    let tagIds: [String]
}

private nonisolated struct InviteListResponse: Decodable {
    let invites: [RemoteInvite]
}

private nonisolated struct CreateInviteResponse: Decodable {
    let invite: RemoteInvite
    let url: URL

    var created: CreatedInvite { CreatedInvite(invite: invite, url: url) }
}

private nonisolated struct PutEntryResponse: Decodable {
    var missingMedia: [String]
}

nonisolated struct RemoteEntryState: Equatable, Sendable {
    var mediaKeys: [String]
    var clientContentHash: String?
}

private nonisolated struct GetEntryResponse: Decodable {
    struct Item: Decodable {
        struct Media: Decodable { var assetKey: String }
        var media: [Media]
        var clientContentHash: String?

        var state: RemoteEntryState {
            RemoteEntryState(mediaKeys: media.map(\.assetKey), clientContentHash: clientContentHash)
        }
    }

    var entry: Item
}

private nonisolated struct ErrorEnvelope: Decodable {
    nonisolated struct Body: Decodable {
        var code: String
        var message: String
        /// Present when media was refused for carrying location metadata.
        var metadata: [String]?
    }
    var error: Body
}
