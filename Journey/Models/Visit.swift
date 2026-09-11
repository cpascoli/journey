import CoreLocation
import Foundation
import SwiftData

@Model
final class Visit {
    var id: UUID = UUID()
    var arrival: Date = Date.distantPast
    var departure: Date?
    var latitude: Double = 0
    var longitude: Double = 0
    var horizontalAccuracy: Double = 0
    var placeName: String?
    var entries: [Entry]? = []

    init(arrival: Date, coordinate: CLLocationCoordinate2D) {
        self.arrival = arrival
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
