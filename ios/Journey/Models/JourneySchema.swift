import CoreLocation
import Foundation
import SwiftData

// Each schema matches a model shape that shipped before versioning was introduced.
// Keeping every checksum in the plan lets SwiftData recognize those unversioned stores.
enum JourneySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [Journal.self, Entry.self, Visit.self]

    @Model
    final class Journal {
        var id: UUID = UUID()
        var name: String = ""
        var isDefault: Bool = false
        var createdAt: Date = Date.now
        @Relationship(deleteRule: .cascade, inverse: \Entry.journal) var entries: [Entry]? = []

        init(name: String, isDefault: Bool = false) {
            self.name = name
            self.isDefault = isDefault
        }
    }

    @Model
    final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var date: Date = Date.now
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var placeName: String?
        var latitude: Double?
        var longitude: Double?
        var mediaAssetIDs: [String] = []
        var isAIGenerated: Bool = false
        var publishStatusRaw: String = "notPublished"
        var remoteID: String?
        var publishedAt: Date?
        var sharedLocationPrecisionRaw: String = "city"
        var journal: Journal?
        @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []

        init() {}
    }

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
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }
}

enum JourneySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any PersistentModel.Type] = [Journal.self, Entry.self, Visit.self]

    @Model
    final class Journal {
        var id: UUID = UUID()
        var name: String = ""
        var isDefault: Bool = false
        var createdAt: Date = Date.now
        @Relationship(deleteRule: .cascade, inverse: \Entry.journal) var entries: [Entry]? = []

        init(name: String, isDefault: Bool = false) {
            self.name = name
            self.isDefault = isDefault
        }
    }

    @Model
    final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var date: Date = Date.now
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var placeName: String?
        var latitude: Double?
        var longitude: Double?
        var mediaAssetIDs: [String] = []
        var isAIGenerated: Bool = false
        var narrative: String = ""
        var narrativeSourceRaw: String = "user"
        var translationLanguage: String = ""
        var translatedTitle: String = ""
        var translatedBody: String = ""
        var translatedNarrative: String = ""
        var publishStatusRaw: String = "notPublished"
        var remoteID: String?
        var publishedAt: Date?
        var sharedLocationPrecisionRaw: String = "city"
        var journal: Journal?
        @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []

        init() {}
    }

    @Model
    final class Visit {
        var id: UUID = UUID()
        var arrival: Date = Date.distantPast
        var departure: Date?
        var latitude: Double = 0
        var longitude: Double = 0
        var horizontalAccuracy: Double = 0
        var placeName: String?
        var sourceRaw: String = "tracked"
        var entries: [Entry]? = []

        init(arrival: Date, coordinate: CLLocationCoordinate2D) {
            self.arrival = arrival
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }
}

enum JourneySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static let models: [any PersistentModel.Type] = [Journal.self, Entry.self, Visit.self, Tag.self]

    @Model
    final class Journal {
        var id: UUID = UUID()
        var name: String = ""
        var isDefault: Bool = false
        var createdAt: Date = Date.now
        @Relationship(deleteRule: .cascade, inverse: \Entry.journal) var entries: [Entry]? = []

        init(name: String, isDefault: Bool = false) {
            self.name = name
            self.isDefault = isDefault
        }
    }

    @Model
    final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var date: Date = Date.now
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var placeName: String?
        var latitude: Double?
        var longitude: Double?
        var mediaAssetIDs: [String] = []
        var isAIGenerated: Bool = false
        var narrative: String = ""
        var narrativeSourceRaw: String = "user"
        var translationLanguage: String = ""
        var translatedTitle: String = ""
        var translatedBody: String = ""
        var translatedNarrative: String = ""
        var publishStatusRaw: String = "notPublished"
        var remoteID: String?
        var publishedAt: Date?
        var sharedLocationPrecisionRaw: String = "city"
        var journal: Journal?
        @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []
        @Relationship(inverse: \Tag.entries) var tags: [Tag]? = []

        init() {}
    }

    @Model
    final class Visit {
        var id: UUID = UUID()
        var arrival: Date = Date.distantPast
        var departure: Date?
        var latitude: Double = 0
        var longitude: Double = 0
        var horizontalAccuracy: Double = 0
        var placeName: String?
        var sourceRaw: String = "tracked"
        var entries: [Entry]? = []

        init(arrival: Date, coordinate: CLLocationCoordinate2D) {
            self.arrival = arrival
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorName: String = "blue"
        var createdAt: Date = Date.now
        var entries: [Entry]? = []

        init(name: String, colorName: String = "blue") {
            self.name = name
            self.colorName = colorName
        }
    }
}

enum JourneySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static let models: [any PersistentModel.Type] = [Journal.self, Entry.self, Visit.self, Tag.self]

    @Model
    final class Journal {
        var id: UUID = UUID()
        var name: String = ""
        var isDefault: Bool = false
        var createdAt: Date = Date.now
        @Relationship(deleteRule: .cascade, inverse: \Entry.journal) var entries: [Entry]? = []

        init(name: String, isDefault: Bool = false) {
            self.name = name
            self.isDefault = isDefault
        }
    }

    @Model
    final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var date: Date = Date.now
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var placeName: String?
        var latitude: Double?
        var longitude: Double?
        var mediaAssetIDs: [String] = []
        var isAIGenerated: Bool = false
        var narrative: String = ""
        var narrativeSourceRaw: String = "user"
        var translationLanguage: String = ""
        var translatedTitle: String = ""
        var translatedBody: String = ""
        var translatedNarrative: String = ""
        var publishStatusRaw: String = "notPublished"
        var remoteID: String?
        var publishedAt: Date?
        var sharedLocationPrecisionRaw: String = "city"
        var visibilityRaw: String = "private"
        var journal: Journal?
        @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []
        @Relationship(inverse: \Tag.entries) var tags: [Tag]? = []

        init() {}
    }

    @Model
    final class Visit {
        var id: UUID = UUID()
        var arrival: Date = Date.distantPast
        var departure: Date?
        var latitude: Double = 0
        var longitude: Double = 0
        var horizontalAccuracy: Double = 0
        var placeName: String?
        var sourceRaw: String = "tracked"
        var entries: [Entry]? = []

        init(arrival: Date, coordinate: CLLocationCoordinate2D) {
            self.arrival = arrival
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorName: String = "blue"
        var createdAt: Date = Date.now
        var entries: [Entry]? = []

        init(name: String, colorName: String = "blue") {
            self.name = name
            self.colorName = colorName
        }
    }
}

enum JourneySchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static let models: [any PersistentModel.Type] = [Journal.self, Entry.self, Visit.self, Tag.self]

    @Model
    final class Journal {
        var id: UUID = UUID()
        var name: String = ""
        var isDefault: Bool = false
        var createdAt: Date = Date.now
        @Relationship(deleteRule: .cascade, inverse: \Entry.journal) var entries: [Entry]? = []

        init(name: String, isDefault: Bool = false) {
            self.name = name
            self.isDefault = isDefault
        }
    }

    @Model
    final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var date: Date = Date.now
        var localDay: String = ""
        var timeZoneIdentifier: String = ""
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var placeName: String?
        var latitude: Double?
        var longitude: Double?
        var mediaAssetIDs: [String] = []
        var isAIGenerated: Bool = false
        var narrative: String = ""
        var narrativeSourceRaw: String = "user"
        var translationLanguage: String = ""
        var translatedTitle: String = ""
        var translatedBody: String = ""
        var translatedNarrative: String = ""
        var publishStatusRaw: String = "notPublished"
        var remoteID: String?
        var publishedAt: Date?
        var sharedLocationPrecisionRaw: String = "city"
        var visibilityRaw: String = "private"
        var journal: Journal?
        @Relationship(inverse: \Visit.entries) var visits: [Visit]? = []
        @Relationship(inverse: \Tag.entries) var tags: [Tag]? = []

        init() {}
    }

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
        var sourceRaw: String = "tracked"
        var entries: [Entry]? = []

        init(arrival: Date, coordinate: CLLocationCoordinate2D) {
            self.arrival = arrival
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorName: String = "blue"
        var createdAt: Date = Date.now
        var entries: [Entry]? = []

        init(name: String, colorName: String = "blue") {
            self.name = name
            self.colorName = colorName
        }
    }
}

enum JourneySchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Journal.self, Entry.self, Visit.self, Tag.self, PublishDestination.self, PublishOperation.self,
    ]
}

enum JourneySchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Journal.self, Entry.self, Visit.self, Tag.self, PublishDestination.self, PublishOperation.self,
        EntryMetadataCache.self,
    ]
}

enum JourneyMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        JourneySchemaV1.self,
        JourneySchemaV2.self,
        JourneySchemaV3.self,
        JourneySchemaV4.self,
        JourneySchemaV5.self,
        JourneySchemaV6.self,
        JourneySchemaV7.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: JourneySchemaV1.self, toVersion: JourneySchemaV2.self),
        .lightweight(fromVersion: JourneySchemaV2.self, toVersion: JourneySchemaV3.self),
        .lightweight(fromVersion: JourneySchemaV3.self, toVersion: JourneySchemaV4.self),
        .custom(
            fromVersion: JourneySchemaV4.self,
            toVersion: JourneySchemaV5.self,
            willMigrate: nil
        ) { context in
            let entries = try context.fetch(FetchDescriptor<JourneySchemaV5.Entry>())
            for entry in entries where entry.localDay.isEmpty || entry.timeZoneIdentifier.isEmpty {
                entry.localDay = LocalDay.string(for: entry.date, timeZone: .current)
                entry.timeZoneIdentifier = TimeZone.current.identifier
            }
            let visits = try context.fetch(FetchDescriptor<JourneySchemaV5.Visit>())
            for visit in visits where visit.localDay.isEmpty || visit.timeZoneIdentifier.isEmpty {
                visit.localDay = LocalDay.string(for: visit.arrival, timeZone: .current)
                visit.timeZoneIdentifier = TimeZone.current.identifier
            }
            try context.save()
        },
        .lightweight(fromVersion: JourneySchemaV5.self, toVersion: JourneySchemaV6.self),
        .lightweight(fromVersion: JourneySchemaV6.self, toVersion: JourneySchemaV7.self),
    ]
}
