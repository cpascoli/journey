import CoreLocation
import MapKit
import SwiftData

enum PlaceNamer {
    struct CoordinateDetails: Sendable {
        var locality: String?
        var timeZone: TimeZone?
    }

    /// Names visits that don't have a name yet. One request at a time with a pause,
    /// because Apple throttles geocoding; a failed lookup is retried next time.
    static func nameUnnamed(_ visits: [Visit], in context: ModelContext) async {
        for visit in visits where visit.placeName == nil {
            guard !Task.isCancelled else { return }
            guard let request = MKReverseGeocodingRequest(location: visit.location),
                  let item = (try? await request.mapItems)?.first else { continue }
            visit.placeName = item.name
            if let timeZone = item.timeZone {
                LocalDay.capture(visit, timeZone: timeZone)
            }
            try? context.save()
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// Refreshes derived location data only when needed. A failed lookup leaves
    /// the last useful values in place so a transient geocoder failure cannot
    /// erase the published city or change the travel day.
    static func refresh(
        entry: Entry,
        cache: EntryMetadataCache,
        lookup: (Double, Double) async -> CoordinateDetails? = coordinateDetails
    ) async {
        guard let latitude = entry.latitude, let longitude = entry.longitude else { return }
        guard !cache.matches(latitude: latitude, longitude: longitude) else { return }
        guard let details = await lookup(latitude, longitude) else { return }
        guard entry.latitude == latitude, entry.longitude == longitude else { return }

        if let locality = details.locality {
            cache.locality = locality
            cache.geocodedLatitude = latitude
            cache.geocodedLongitude = longitude
        }
        if let timeZone = details.timeZone {
            cache.timeZoneIdentifier = timeZone.identifier
            LocalDay.capture(entry, timeZone: timeZone)
        }
    }

    /// The town/city and timezone derived in one reverse-geocoding request.
    static func coordinateDetails(latitude: Double, longitude: Double) async -> CoordinateDetails? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
              let item = (try? await request.mapItems)?.first else { return nil }
        return CoordinateDetails(locality: item.addressRepresentations?.cityName, timeZone: item.timeZone)
    }
}
