import SwiftData
import SwiftUI

@main
struct JourneyApp: App {
    private let container: ModelContainer
    @State private var locationService: LocationService

    init() {
        let container: ModelContainer
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: Self.isDemo)
            container = try ModelContainer(for: Journal.self, Entry.self, Visit.self, Tag.self, configurations: configuration)
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
        Journal.ensureDefault(in: container.mainContext)
        #if DEBUG
        if Self.isDemo {
            DemoData.seed(in: container.mainContext)
        }
        #endif
        self.container = container
        // Created at launch so visits delivered while the app was relaunched in the background are captured.
        _locationService = State(initialValue: LocationService(context: container.mainContext))
    }

    private static var isDemo: Bool {
        #if DEBUG
        DemoData.isEnabled
        #else
        false
        #endif
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
    @State private var tab = RootTab.write
    @AppStorage("appearance") private var appearance = AppearanceMode.system

    private var journal: Journal? {
        journals.first { $0.id.uuidString == selectedJournalID }
            ?? journals.first { $0.isDefault }
            ?? journals.first
    }

    var body: some View {
        if let journal {
            // Write stays the first tab: DemoWalkthrough expects to land on the day view.
            let subtitle = journals.count > 1 ? journal.name : nil
            TabView(selection: $tab) {
                Tab("Write", systemImage: "square.and.pencil", value: RootTab.write) {
                    NavigationStack {
                        DayView(day: $day, journal: journal)
                            .journalSubtitle(subtitle)
                    }
                }
                Tab("Calendar", systemImage: "calendar", value: RootTab.calendar) {
                    NavigationStack {
                        CalendarView(journal: journal)
                            .journalSubtitle(subtitle)
                    }
                }
                Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                    NavigationStack {
                        SettingsView(journals: journals, current: journal, selectedID: $selectedJournalID)
                    }
                }
            }
            .preferredColorScheme(appearance.colorScheme)
        }
    }
}

private enum RootTab {
    case write, calendar, settings
}

private extension View {
    /// Names the active journal under the title, only when there's more than one to confuse it with.
    @ViewBuilder
    func journalSubtitle(_ name: String?) -> some View {
        if let name {
            navigationSubtitle(name)
        } else {
            self
        }
    }
}
