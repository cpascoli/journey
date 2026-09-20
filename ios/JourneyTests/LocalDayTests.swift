import CoreLocation
import XCTest
@testable import Journey

final class LocalDayTests: XCTestCase {
    func testLocalDayUsesEventTimeZoneAcrossDateBoundary() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T17:30:00Z"))
        let bangkok = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        XCTAssertEqual(LocalDay.string(for: instant, timeZone: bangkok), "2026-09-18")
        XCTAssertEqual(LocalDay.string(for: instant, timeZone: losAngeles), "2026-09-17")
    }

    func testEntryAndVisitKeepCapturedDay() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T00:30:00Z"))
        let honolulu = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        let entry = Entry()
        entry.date = instant
        LocalDay.capture(entry, timeZone: honolulu)
        let visit = Visit(
            arrival: instant,
            coordinate: CLLocationCoordinate2D(latitude: 21.3069, longitude: -157.8583)
        )
        LocalDay.capture(visit, timeZone: honolulu)

        XCTAssertEqual(entry.localDay, "2025-12-31")
        XCTAssertEqual(entry.timeZoneIdentifier, "Pacific/Honolulu")
        XCTAssertEqual(visit.localDay, "2025-12-31")
        XCTAssertEqual(visit.timeZoneIdentifier, "Pacific/Honolulu")
    }

    func testPhotoIntervalsCoverStoredTimeZonesForSameCivilDay() throws {
        let intervals = LocalDay.intervals(
            for: "2026-09-18",
            timeZoneIdentifiers: ["Asia/Bangkok", "America/Los_Angeles", "Asia/Bangkok"]
        )

        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(
            intervals[0].start,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T17:00:00Z"))
        )
        XCTAssertEqual(
            intervals[1].start,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T07:00:00Z"))
        )
    }

    func testPhotoIntervalUsesCalendarDayAcrossDST() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let interval = try XCTUnwrap(LocalDay.interval(for: "2026-11-01", timeZone: newYork))

        XCTAssertEqual(interval.duration, 25 * 60 * 60)
    }

    @MainActor
    func testPublisherUsesStoredDay() async {
        let entry = Entry()
        entry.date = .distantFuture
        entry.localDay = "1999-12-31"

        let payload = await Publisher.payload(for: entry, mediaKeys: [])

        XCTAssertEqual(payload.day, "1999-12-31")
    }

    @MainActor
    func testGeocodingFailureKeepsCachedLocalityAndTimezone() async {
        let entry = Entry()
        entry.date = Date(timeIntervalSince1970: 1_757_877_000)
        entry.latitude = 13.7563
        entry.longitude = 100.5018
        let cache = EntryMetadataCache(entryID: entry.id)
        cache.locality = "Bangkok"
        cache.timeZoneIdentifier = "Asia/Bangkok"
        cache.geocodedLatitude = 1
        cache.geocodedLongitude = 2
        entry.timeZoneIdentifier = "Asia/Bangkok"

        await PlaceNamer.refresh(entry: entry, cache: cache) { _, _ in nil }

        XCTAssertEqual(cache.locality, "Bangkok")
        XCTAssertEqual(cache.timeZoneIdentifier, "Asia/Bangkok")
        XCTAssertEqual(entry.timeZoneIdentifier, "Asia/Bangkok")
    }

    @MainActor
    func testChangedCoordinatesRefreshCachedLocalityAndTimezone() async throws {
        let entry = Entry()
        entry.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T17:30:00Z"))
        entry.latitude = 35.6762
        entry.longitude = 139.6503
        let cache = EntryMetadataCache(entryID: entry.id)
        cache.locality = "Bangkok"
        cache.geocodedLatitude = 13.7563
        cache.geocodedLongitude = 100.5018

        await PlaceNamer.refresh(entry: entry, cache: cache) { _, _ in
            PlaceNamer.CoordinateDetails(
                locality: "Tokyo",
                timeZone: TimeZone(identifier: "Asia/Tokyo")
            )
        }

        XCTAssertEqual(cache.locality, "Tokyo")
        XCTAssertEqual(cache.geocodedLatitude, 35.6762)
        XCTAssertEqual(cache.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(entry.localDay, "2026-09-18")
    }

    @MainActor
    func testTimezoneOnlyLookupKeepsLocalityAndAllowsLocalityRetry() async throws {
        let entry = Entry()
        entry.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T17:30:00Z"))
        entry.latitude = 35.6762
        entry.longitude = 139.6503
        let cache = EntryMetadataCache(entryID: entry.id)
        cache.locality = "Previously known city"
        cache.geocodedLatitude = 13.7563
        cache.geocodedLongitude = 100.5018

        await PlaceNamer.refresh(entry: entry, cache: cache) { _, _ in
            PlaceNamer.CoordinateDetails(locality: nil, timeZone: TimeZone(identifier: "Asia/Tokyo"))
        }

        XCTAssertEqual(cache.locality, "Previously known city")
        XCTAssertFalse(cache.matches(latitude: 35.6762, longitude: 139.6503))
        XCTAssertEqual(cache.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(entry.localDay, "2026-09-18")
    }

    func testInviteAccessLabelDistinguishesUnknownTagsFromNoTags() {
        let known = UUID()
        let unknown = UUID()

        XCTAssertEqual(InviteAccessLabel.text(tagIDs: [], namesByID: [:]), "Untagged entries")
        XCTAssertEqual(
            InviteAccessLabel.text(tagIDs: [known, unknown], namesByID: [known: "Friends"]),
            "Friends, 1 unknown tag"
        )
        XCTAssertEqual(
            InviteAccessLabel.text(tagIDs: [unknown], namesByID: [:]),
            "1 unknown tag"
        )
    }

    @MainActor
    func testPublisherUsesCachedLocality() async {
        let entry = Entry()
        entry.latitude = 13.7563
        entry.longitude = 100.5018
        let cache = EntryMetadataCache(entryID: entry.id)
        cache.locality = "Bangkok"
        cache.geocodedLatitude = entry.latitude
        cache.geocodedLongitude = entry.longitude

        let payload = await Publisher.payload(for: entry, mediaKeys: [], locationCache: cache)

        XCTAssertEqual(payload.location?.locality, "Bangkok")
    }
}
