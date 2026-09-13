import CoreLocation
import Photos

/// Groups a day's photos and videos under the visits they were taken at.
struct DayTimeline {
    struct Stop: Identifiable {
        let visit: Visit
        var assetIDs: [String] = []
        var id: UUID { visit.id }
    }

    private(set) var stops: [Stop]
    private(set) var looseAssetIDs: [String] = []

    private static let timeSlack: TimeInterval = 10 * 60
    static let maxDistance: CLLocationDistance = 250

    init(visits: [Visit], assets: [PHAsset], now: Date = .now) {
        stops = visits.map { Stop(visit: $0) }
        for asset in assets {
            if let index = Self.stopIndex(for: asset, in: stops, now: now) {
                stops[index].assetIDs.append(asset.localIdentifier)
            } else {
                looseAssetIDs.append(asset.localIdentifier)
            }
        }
    }

    private static func stopIndex(for asset: PHAsset, in stops: [Stop], now: Date) -> Int? {
        guard let taken = asset.creationDate else { return nil }
        return stops.firstIndex { stop in
            let visit = stop.visit
            let end = max(visit.departure ?? now, visit.arrival)
            let window = visit.arrival.addingTimeInterval(-timeSlack)...end.addingTimeInterval(timeSlack)
            guard window.contains(taken) else { return false }
            guard let location = asset.location else { return true }
            return location.distance(from: visit.location) <= maxDistance
        }
    }
}
