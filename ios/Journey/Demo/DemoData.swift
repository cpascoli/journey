#if DEBUG
import CoreLocation
import Foundation
import SwiftData

/// Sample Bangkok trip loaded by the `-demo` launch argument into an in-memory store.
/// Visit times and places must match the photos staged by `Tools/stage-demo-photos.swift`.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }

    private struct Stop {
        let name: String
        let arrival: (hour: Int, minute: Int)
        let departure: (hour: Int, minute: Int)
        let latitude: Double
        let longitude: Double
    }

    private static let todayStops = [
        Stop(name: "Wat Arun", arrival: (9, 0), departure: (10, 30), latitude: 13.7437, longitude: 100.4889),
        Stop(name: "Chatuchak Weekend Market", arrival: (12, 0), departure: (14, 0), latitude: 13.7999, longitude: 100.5500),
        Stop(name: "Lumphini Park", arrival: (17, 0), departure: (18, 30), latitude: 13.7314, longitude: 100.5414),
    ]

    static func seed(in context: ModelContext) {
        let main = Journal.ensureDefault(in: context)
        context.insert(Journal(name: "Work Trips"))

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func time(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        for stop in todayStops {
            let visit = Visit(
                arrival: time(today, stop.arrival.hour, stop.arrival.minute),
                coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
            )
            visit.departure = time(today, stop.departure.hour, stop.departure.minute)
            visit.placeName = stop.name
            context.insert(visit)
        }

        let sightseeing = Tag(name: "Sightseeing", color: .purple)
        let food = Tag(name: "Food", color: .orange)
        let friends = Tag(name: "Friends", color: .blue)
        [sightseeing, food, friends].forEach(context.insert)

        addEntry(to: main, in: context, date: time(today, 7, 45), place: "Chao Phraya River",
                 title: "Long-tail boat at dawn",
                 body: "Caught the first boat from Tha Tien. The river was glassy and the city still half asleep.",
                 tags: [sightseeing])
        addEntry(to: main, in: context, date: time(yesterday, 15, 20), place: "Suvarnabhumi Airport",
                 title: "Landed in Bangkok",
                 body: "Thirty-four degrees and a wall of humidity the moment the doors opened.")
        addEntry(to: main, in: context, date: time(yesterday, 20, 30), place: "Yaowarat, Chinatown",
                 title: "Street food crawl",
                 body: "Pepper soup, oyster omelette and far too many mango sticky rices.",
                 tags: [food, friends])
    }

    private static func addEntry(to journal: Journal, in context: ModelContext, date: Date, place: String,
                                 title: String, body: String, tags: [Tag] = []) {
        let entry = Entry()
        context.insert(entry)
        entry.journal = journal
        entry.date = date
        LocalDay.capture(entry, timeZone: .current)
        entry.placeName = place
        entry.title = title
        entry.body = body
        entry.tags = tags
    }
}
#endif
