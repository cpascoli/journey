import SwiftData
import SwiftUI

@main
struct JourneyApp: App {
    private let container: ModelContainer
    @State private var locationService: LocationService

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Journal.self, Entry.self, Visit.self)
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
        Journal.ensureDefault(in: container.mainContext)
        self.container = container
        // Created at launch so visits delivered while the app was relaunched in the background are captured.
        _locationService = State(initialValue: LocationService(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(locationService)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Query(sort: \Journal.createdAt) private var journals: [Journal]
    @AppStorage("selectedJournalID") private var selectedJournalID = ""
    @State private var day = Calendar.current.startOfDay(for: .now)

    private var journal: Journal? {
        journals.first { $0.id.uuidString == selectedJournalID }
            ?? journals.first { $0.isDefault }
            ?? journals.first
    }

    var body: some View {
        NavigationStack {
            if let journal {
                DayView(day: $day, journal: journal)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            JournalMenu(journals: journals, current: journal, selectedID: $selectedJournalID)
                        }
                    }
            }
        }
    }
}
