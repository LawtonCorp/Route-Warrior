import Foundation
import RouteWarriorKit
import SwiftData

// SwiftData models mirroring the kit's value types (SPEC §2.1). CloudKit
// mirroring imposes the shape here: every property optional or defaulted,
// no #Unique, no required relationships. Bulky payloads (track points, stop
// events, alternates) ride as JSON blobs of the kit's own Codable types, so
// the wire format is the kit's and the schema stays boring; scalars that
// queries filter on are real columns.

@Model
public final class TripRecord {
    public var id: UUID = UUID()
    public var startedAt: Date = Date.distantPast
    public var endedAt: Date = Date.distantPast
    public var timezoneID: String = ""
    public var originPlaceID: UUID?
    public var destinationPlaceID: UUID?
    public var variantID: UUID?
    public var distanceM: Double = 0
    public var movingTime: Double = 0
    public var idleTime: Double = 0
    public var snapshotID: UUID?
    public var followedPlan: Bool?
    public var sourceRaw: String = Trip.Source.auto.rawValue
    public var excludedFromStats: Bool = false
    @Attribute(.externalStorage) public var pointsBlob: Data = Data()
    public var stopEventsBlob: Data = Data()

    public init() {}
}

@Model
public final class PlaceRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var radiusM: Double = 75
    public var kindRaw: String = Place.Kind.custom.rawValue
    public var createdAt: Date = Date.distantPast

    public init() {}
}

@Model
public final class VariantRecord {
    public var id: UUID = UUID()
    public var originPlaceID: UUID?
    public var destinationPlaceID: UUID?
    public var polylineEncoded: String = ""
    public var autoName: String = ""
    public var tripCount: Int = 0
    public var signalCount: Int?
    public var stopSignCount: Int?
    public var coverageRaw: String?
    public var inventoryFetchedAt: Date?

    public init() {}
}

@Model
public final class SnapshotRecord {
    public var id: UUID = UUID()
    public var providerRaw: String = PlanSnapshot.Provider.googleRoutes.rawValue
    public var requestedAt: Date = Date.distantPast
    public var destinationPlaceID: UUID?
    public var polylineEncoded: String = ""
    public var distanceM: Double = 0
    public var staticDuration: Double = 0
    public var trafficDuration: Double = 0
    public var alternatesBlob: Data = Data()

    public init() {}
}
