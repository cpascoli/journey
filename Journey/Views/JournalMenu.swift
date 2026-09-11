import SwiftData
import SwiftUI

struct JournalMenu: View {
    let journals: [Journal]
    let current: Journal
    @Binding var selectedID: String

    @Environment(\.modelContext) private var context
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            Picker("Journal", selection: Binding(get: { current.id.uuidString }, set: { selectedID = $0 })) {
                ForEach(journals) { journal in
                    Text(journal.name).tag(journal.id.uuidString)
                }
            }
            Divider()
            Button("New Journal…", systemImage: "plus") {
                newName = ""
                isNaming = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.name)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityIdentifier("journalMenu")
        .alert("New Journal", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Create", action: createJournal)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func createJournal() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let journal = Journal(name: name)
        context.insert(journal)
        selectedID = journal.id.uuidString
    }
}
