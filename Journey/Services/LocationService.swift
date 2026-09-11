import CoreLocation
import MapKit
import SwiftData

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        startIfAuthorized()
    }

    var isTrackingDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestAuthorizationIfNeeded() {
        guard authorization == .notDetermined else { return }
        manager.requestAlwaysAuthorization()
    }

    private func startIfAuthorized() {
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            manager.startMonitoringVisits()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.startIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // CoreLocation reports unknown arrival/departure with sentinel dates.
        guard visit.arrivalDate != .distantPast else { return }
        let arrival = visit.arrivalDate
        let departure = visit.departureDate == .distantFuture ? nil : visit.departureDate
        let coordinate = visit.coordinate
        let accuracy = visit.horizontalAccuracy
        Task { @MainActor in
            self.record(arrival: arrival, departure: departure, coordinate: coordinate, accuracy: accuracy)
        }
    }

    // A visit is reported once on arrival and again on departure with the same arrival date.
    private func record(arrival: Date, departure: Date?, coordinate: CLLocationCoordinate2D, accuracy: Double) {
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival == arrival })
        let visit: Visit
        if let existing = try? context.fetch(descriptor).first {
            visit = existing
        } else {
            visit = Visit(arrival: arrival, coordinate: coordinate)
            context.insert(visit)
        }
        visit.departure = departure
        visit.horizontalAccuracy = accuracy
        try? context.save()

        if visit.placeName == nil {
            Task { await resolvePlaceName(for: visit) }
        }
    }

    private func resolvePlaceName(for visit: Visit) async {
        guard let request = MKReverseGeocodingRequest(location: visit.location),
              let item = (try? await request.mapItems)?.first
        else { return }
        visit.placeName = item.name
        try? context.save()
    }
}
