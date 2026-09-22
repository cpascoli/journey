import SwiftUI

/// The Sharing tab: who can read the journal, and what they have said about it.
///
/// Its own tab rather than a section inside Settings, because sharing is
/// something the journal does regularly, while settings are set once.
struct SharingView: View {
    @Environment(CommentInbox.self) private var inbox

    var body: some View {
        List {
            Section {
                NavigationLink {
                    InviteManagementView()
                } label: {
                    Label("Invitations", systemImage: "person.2")
                }
                NavigationLink {
                    CommentsView()
                } label: {
                    Label("Comments", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(inbox.unseenCount)
            } footer: {
                Text("An invitation sees an entry only when it includes every tag on that entry. Each invitation has its own private conversation with you.")
            }

            if JourneyAPI.configured() == nil {
                Section {
                    Label(
                        "Add your website and owner key in Settings → Website to invite anyone.",
                        systemImage: "key"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sharing")
    }
}
