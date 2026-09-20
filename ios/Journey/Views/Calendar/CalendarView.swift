import SwiftData
import SwiftUI

enum CalendarScale: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

/// Read mode: browse the journal by day, week, month or year, and read each day as a page.
/// Tapping a month or a day zooms in to it.
struct CalendarView: View {
    let journal: Journal

    @Query(sort: \Entry.date) private var allEntries: [Entry]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var tagFilter: UUID?
    @State private var scale = CalendarScale.month
    @State private var anchor = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current

    var body: some View {
        // A filter whose tag was deleted simply stops applying.
        let activeTag = tags.first { $0.id == tagFilter }
        let entriesByDay = Dictionary(grouping: allEntries.filter { entry in
            entry.journal?.id == journal.id
                && (activeTag == nil || (entry.tags ?? []).contains { $0.id == activeTag?.id })
        }) {
            $0.calendarDay
        }
        content(entriesByDay)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Picker("Scale", selection: $scale.animation()) {
                            ForEach(CalendarScale.allCases) { scale in
                                Text(scale.title).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        if !tags.isEmpty {
                            tagFilterMenu(active: activeTag)
                        }
                        Button("Today") {
                            withAnimation { anchor = calendar.startOfDay(for: .now) }
                        }
                        .disabled(calendar.isDate(anchor, equalTo: .now, toGranularity: scale.component))
                    }
                    if let activeTag {
                        HStack(spacing: 6) {
                            Text("Only")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TagChip(tag: activeTag)
                            Button("Show All") { tagFilter = nil }
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Previous", systemImage: "chevron.left") { shift(by: -1) }
                    Button("Next", systemImage: "chevron.right") { shift(by: 1) }
                }
            }
    }

    @ViewBuilder
    private func content(_ entriesByDay: [Date: [Entry]]) -> some View {
        switch scale {
        case .day:
            JournalPageView(day: anchor, entries: entriesByDay[anchor] ?? [], journal: journal)
        case .week:
            WeekOverview(days: weekDays, entriesByDay: entriesByDay, onOpen: open)
        case .month:
            MonthOverview(month: anchor, entriesByDay: entriesByDay, onOpen: open)
        case .year:
            YearOverview(year: anchor, entriesByDay: entriesByDay) { month in
                withAnimation {
                    anchor = month
                    scale = .month
                }
            }
        }
    }

    private func tagFilterMenu(active: Tag?) -> some View {
        Menu {
            Picker("Show", selection: $tagFilter) {
                Text("All Entries").tag(UUID?.none)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
        } label: {
            Image(systemName: active == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
        }
        .accessibilityLabel(active.map { "Showing \($0.name)" } ?? "Filter by Tag")
    }

    private var weekDays: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var title: String {
        switch scale {
        case .day:
            return anchor.formatted(.dateTime.weekday(.abbreviated).day().month())
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else { return "" }
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            return "\(first.formatted(style)) – \(last.formatted(style))"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .year:
            return anchor.formatted(.dateTime.year())
        }
    }

    private func shift(by value: Int) {
        guard let next = calendar.date(byAdding: scale.component, value: value, to: anchor) else { return }
        withAnimation { anchor = calendar.startOfDay(for: next) }
    }

    private func open(_ day: Date) {
        withAnimation {
            anchor = day
            scale = .day
        }
    }
}

enum CalendarMath {
    /// The days of `date`'s month, preceded by nil padding so the first day lands in its weekday column.
    static func monthCells(for date: Date, calendar: Calendar = .current) -> [Date?] {
        guard let first = calendar.dateInterval(of: .month, for: date)?.start,
              let count = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: leading) + days
    }

    /// Very short weekday symbols, starting from the calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
