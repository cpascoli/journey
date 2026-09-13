import SwiftUI

/// Twelve small months, with a dot on every day that has an entry.
struct YearOverview: View {
    let year: Date
    let entriesByDay: [Date: [Entry]]
    let onOpenMonth: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let start = calendar.dateInterval(of: .year, for: year)?.start ?? year
        let months = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 24) {
                ForEach(months, id: \.self) { month in
                    Button { onOpenMonth(month) } label: {
                        MiniMonth(month: month, entriesByDay: entriesByDay)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

private struct MiniMonth: View {
    let month: Date
    let entriesByDay: [Date: [Entry]]

    var body: some View {
        let calendar = Calendar.current
        let cells = CalendarMath.monthCells(for: month)
        let count = cells.compactMap { $0 }.reduce(0) { $0 + (entriesByDay[$1]?.count ?? 0) }
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        VStack(alignment: .leading, spacing: 6) {
            Text(month.formatted(.dateTime.month(.abbreviated)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Circle()
                            .fill(entriesByDay[day] != nil ? Color.accentColor : Color.secondary.opacity(0.18))
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            Text(count == 0 ? " " : (count == 1 ? "1 entry" : "\(count) entries"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}
