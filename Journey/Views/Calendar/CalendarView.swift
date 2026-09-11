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
    @State private var scale = CalendarScale.month
    @State private var anchor = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current

    var body: some View {
        let entriesByDay = Dictionary(grouping: allEntries.filter { $0.journal?.id == journal.id }) {
            calendar.startOfDay(for: $0.date)
        }
        content(entriesByDay)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Scale", selection: $scale.animation()) {
                        ForEach(CalendarScale.allCases) { scale in
                            Text(scale.title).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button("Today") {
                        withAnimation { anchor = calendar.startOfDay(for: .now) }
                    }
                    .disabled(calendar.isDate(anchor, equalTo: .now, toGranularity: scale.component))
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
