import Foundation

enum LocalDay {
    static func string(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from value: String, calendar: Calendar = .current) -> Date? {
        guard let components = components(from: value) else { return nil }
        return calendar.date(from: components)
    }

    static func interval(for value: String, timeZone: TimeZone) -> DateInterval? {
        guard let components = components(from: value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func intervals(
        for value: String,
        timeZoneIdentifiers: [String],
        fallback: TimeZone = .current
    ) -> [DateInterval] {
        let identifiers = timeZoneIdentifiers.isEmpty ? [fallback.identifier] : timeZoneIdentifiers
        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let timeZone = TimeZone(identifier: identifier) ?? fallback
            guard seen.insert(timeZone.identifier).inserted else { return nil }
            return interval(for: value, timeZone: timeZone)
        }
    }

    private static func components(from value: String) -> DateComponents? {
        let values = value.split(separator: "-", omittingEmptySubsequences: false)
        guard values.count == 3,
              let year = Int(values[0]),
              let month = Int(values[1]),
              let day = Int(values[2]) else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    static func timeZone(identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? .current
    }

    static func capture(_ entry: Entry, timeZone: TimeZone) {
        entry.timeZoneIdentifier = timeZone.identifier
        entry.localDay = string(for: entry.date, timeZone: timeZone)
    }

    static func capture(_ visit: Visit, timeZone: TimeZone) {
        visit.timeZoneIdentifier = timeZone.identifier
        visit.localDay = string(for: visit.arrival, timeZone: timeZone)
    }
}

extension Entry {
    var calendarDay: Date {
        LocalDay.date(from: localDay)
            ?? Calendar.current.startOfDay(for: date)
    }
}

extension Visit {
    var calendarDay: Date {
        LocalDay.date(from: localDay)
            ?? Calendar.current.startOfDay(for: arrival)
    }
}
