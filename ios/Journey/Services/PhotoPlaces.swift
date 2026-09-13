import CoreLocation
import Photos
import SwiftData

/// Rebuilds places for times the app wasn't tracking, from where and when photos were taken.
enum PhotoPlaces {
    // Same as the matching distance, so every photo matches the visit it produced
    // and reopening a day finds nothing left to do.
    private static let radius = DayTimeline.maxDistance
    private static let maxGap: TimeInterval = 2 * 60 * 60

    /// Puts each located photo on a photo-derived visit close by in space and time,
    /// extending it, or starts a new one. Returns the visits it created.
    @discardableResult
    static func addVisits(for assets: [PHAsset], extending existing: [Visit], in context: ModelContext) -> [Visit] {
        let photos = assets
            .compactMap { asset -> (date: Date, location: CLLocation)? in
                guard let date = asset.creationDate,
                      let location = asset.location,
                      CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
                return (date, location)
            }
            .sorted { $0.date < $1.date }
        guard !photos.isEmpty else { return [] }

        var visits = existing.filter { $0.source == .photos }
        var created: [Visit] = []
        for photo in photos {
            if let visit = visits.first(where: { covers($0, photo.date, photo.location) }) {
                visit.arrival = min(visit.arrival, photo.date)
                visit.departure = max(visit.departure ?? visit.arrival, photo.date)
            } else {
                let visit = Visit(arrival: photo.date, coordinate: photo.location.coordinate)
                visit.departure = photo.date
                visit.source = .photos
                context.insert(visit)
                visits.append(visit)
                created.append(visit)
            }
        }
        try? context.save()
        return created
    }

    private static func covers(_ visit: Visit, _ date: Date, _ location: CLLocation) -> Bool {
        let end = visit.departure ?? visit.arrival
        return date >= visit.arrival.addingTimeInterval(-maxGap)
            && date <= end.addingTimeInterval(maxGap)
            && location.distance(from: visit.location) <= radius
    }
}
