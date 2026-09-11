import SwiftUI

/// A month grid where days with entries show their first photo, with the month's entries listed below.
struct MonthOverview: View {
    let month: Date
    let entriesByDay: [Date: [Entry]]
    let onOpen: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let symbols = CalendarMath.weekdaySymbols()
        let monthDays = entriesByDay
            .filter { calendar.isDate($0.key, equalTo: month, toGranularity: .month) }
            .sorted { $0.key < $1.key }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 6) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(symbols.indices, id: \.self) { index in
                            Text(symbols[index])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(CalendarMath.monthCells(for: month).enumerated()), id: \.offset) { _, day in
                            if let day {
                                Button { onOpen(day) } label: {
                                    DayCell(day: day, entries: entriesByDay[day] ?? [])
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }

                if monthDays.isEmpty {
                    Text("No entries this month.")
                        .font(.system(.body, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(monthDays, id: \.key) { day, entries in
                            Button { onOpen(day) } label: {
                                DaySummaryRow(day: day, entries: entries)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private struct DayCell: View {
    let day: Date
    let entries: [Entry]

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let photo = entries.lazy.compactMap(\.mediaAssetIDs.first).first
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let photo {
                    AssetThumbnail(localIdentifier: photo, size: nil)
                        .overlay(Color.black.opacity(0.25))
                } else if !entries.isEmpty {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18))
                }
            }
            .overlay(alignment: .topLeading) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.weight(isToday || !entries.isEmpty ? .bold : .regular))
                    .foregroundStyle(photo != nil ? Color.white : (isToday ? Color.accentColor : Color.primary))
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                if entries.count > 1 {
                    Text("\(entries.count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: Capsule())
                        .padding(3)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
    }
}

/// One day in a list: date, entry titles and places, and a photo.
struct DaySummaryRow: View {
    let day: Date
    let entries: [Entry]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(.title2, design: .serif, weight: .semibold))
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries.prefix(3)) { entry in
                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                        .font(.system(.body, design: .serif))
                        .lineLimit(1)
                }
                let places = Array(NSOrderedSet(array: entries.compactMap(\.placeName))) as? [String] ?? []
                if !places.isEmpty {
                    Text(places.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let photo = entries.lazy.compactMap(\.mediaAssetIDs.first).first {
                AssetThumbnail(localIdentifier: photo, size: 48)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
