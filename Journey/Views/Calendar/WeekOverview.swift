import SwiftUI

/// The seven days of a week, each with its entries and a strip of their photos.
struct WeekOverview: View {
    let days: [Date]
    let entriesByDay: [Date: [Entry]]
    let onOpen: (Date) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let entries = entriesByDay[day] ?? []
                    Button { onOpen(day) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            if entries.isEmpty {
                                HStack(alignment: .top, spacing: 14) {
                                    DayBadge(day: day)
                                    Text("—")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 14)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10)
                                .contentShape(.rect)
                            } else {
                                DaySummaryRow(day: day, entries: entries)
                                let media = entries.flatMap(\.mediaAssetIDs)
                                if media.count > 1 {
                                    AssetStrip(ids: Array(media.prefix(8)), size: 52)
                                        .padding(.leading, 58)
                                        .padding(.bottom, 10)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct DayBadge: View {
    let day: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(day.formatted(.dateTime.day()))
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.accentColor : Color.primary)
        }
        .frame(width: 44)
    }
}
