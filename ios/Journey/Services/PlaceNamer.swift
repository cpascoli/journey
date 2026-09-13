import MapKit
import SwiftData

enum PlaceNamer {
    /// Names visits that don't have a name yet. One request at a time with a pause,
    /// because Apple throttles geocoding; a failed lookup is retried next time.
    static func nameUnnamed(_ visits: [Visit], in context: ModelContext) async {
        for visit in visits where visit.placeName == nil {
            guard !Task.isCancelled else { return }
            guard let request = MKReverseGeocodingRequest(location: visit.location),
                  let item = (try? await request.mapItems)?.first else { continue }
            visit.placeName = item.name
            try? context.save()
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
