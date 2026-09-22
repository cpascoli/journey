import SwiftUI

nonisolated enum CommentSummary {
    /// What a thread row says beneath the entry title.
    static func text(thread: RemoteCommentThread) -> String {
        var parts = [thread.inviteName]
        parts.append(thread.commentCount == 1 ? "1 comment" : "\(thread.commentCount) comments")
        if thread.inviteRevoked { parts.append("revoked") }
        return parts.joined(separator: " · ")
    }
}

/// Reader conversations, newest first. Each is private to one invitation, so
/// an entry commented on by two people shows as two separate threads.
struct CommentsView: View {
    @State private var threads: [RemoteCommentThread] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading, threads.isEmpty {
                ProgressView()
            } else if threads.isEmpty {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("When someone you invited comments on an entry, it appears here.")
                )
            } else {
                ForEach(threads) { thread in
                    NavigationLink {
                        CommentThreadView(thread: thread) { await reload() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(thread.entryTitle.isEmpty ? "Untitled entry" : thread.entryTitle)
                                Spacer()
                                if thread.unseenCount > 0 {
                                    Text("\(thread.unseenCount)")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(CommentSummary.text(thread: thread))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Comments")
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Comments", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        guard let api = JourneyAPI.configured() else {
            errorMessage = "Add the website and owner key in Settings first."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await api.commentThreads()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One conversation, with the reader's comments and the owner's replies.
private struct CommentThreadView: View {
    let thread: RemoteCommentThread
    let onChange: () async -> Void

    @State private var comments: [RemoteComment] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if isLoading, comments.isEmpty {
                    ProgressView()
                } else {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.isOwner ? "You" : thread.inviteName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(comment.isOwner ? Color.accentColor : .secondary)
                            Text(comment.body)
                        }
                        .frame(maxWidth: .infinity, alignment: comment.isOwner ? .trailing : .leading)
                        .multilineTextAlignment(comment.isOwner ? .trailing : .leading)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(comment)
                            }
                        }
                    }
                }
            } header: {
                Text(thread.entryTitle.isEmpty ? "Untitled entry" : thread.entryTitle)
            } footer: {
                if thread.inviteRevoked {
                    Text("This invitation is revoked, so \(thread.inviteName) can no longer read the journal or your replies.")
                }
            }

            Section {
                TextField("Reply to \(thread.inviteName)", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                Button(isSending ? "Sending…" : "Send Reply") { send() }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(thread.inviteName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let api = JourneyAPI.configured() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await api.comments(entryID: thread.entryId, inviteID: thread.inviteId)
            // Opening the thread is what counts as having read it.
            if thread.unseenCount > 0 {
                try await api.markCommentsSeen(entryID: thread.entryId, inviteID: thread.inviteId)
                await onChange()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() {
        guard let api = JourneyAPI.configured() else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await api.replyToComment(
                    entryID: thread.entryId, inviteID: thread.inviteId, body: body
                )
                draft = ""
                await load()
                await onChange()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private func delete(_ comment: RemoteComment) {
        guard let api = JourneyAPI.configured() else { return }
        Task {
            do {
                try await api.deleteComment(id: comment.id)
                await load()
                await onChange()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
