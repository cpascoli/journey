import CoreLocation
import Foundation
import SwiftData

@Model
final class Visit {
    var id: UUID = UUID()
    var arrival: Date = Date.distantPast
    var departure: Date?
    var localDay: String = ""
    var timeZoneIdentifier: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var horizontalAccuracy: Double = 0
    var placeName: String?
    var sourceRaw: String = VisitSource.tracked.rawValue
    var entries: [Entry]? = []

    init(arrival: Date, coordinate: CLLocationCoordinate2D) {
        self.arrival = arrival
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        LocalDay.capture(self, timeZone: .current)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var source: VisitSource {
        get { VisitSource(rawValue: sourceRaw) ?? .tracked }
        set { sourceRaw = newValue.rawValue }
    }
}

/// `tracked`: recorded by Core Location. `photos`: rebuilt from where and when photos were taken.
nonisolated enum VisitSource: String, Codable, Sendable {
    case tracked, photos
}
