import Foundation
import RouteWarriorKit
import SwiftData

/// Kit value ↔ record mapping. Encoding failures are programmer errors
/// (the kit types are plain Codable structs), but they surface as thrown
/// errors rather than crashes so a corrupt blob can never take the app down.
public enum StoreMappingError: Error {
    case corruptBlob(String)
    case corruptPolyline(String)
}

public extension TripRecord {
    convenience init(_ trip: Trip) throws {
        self.init()
        try update(from: trip)
    }

    func update(from trip: Trip) throws {
        id = trip.id
        startedAt = trip.startedAt
        endedAt = trip.endedAt
        timezoneID = trip.timezoneID
        originPlaceID = trip.originPlaceID
        destinationPlaceID = trip.destinationPlaceID
        variantID = trip.variantID
        distanceM = trip.distanceM
        movingTime = trip.movingTime
        idleTime = trip.idleTime
        snapshotID = trip.snapshotID
        followedPlan = trip.followedPlan
        altSnapshotID = trip.altSnapshotID
        followedAltPlan = trip.followedAltPlan
        sourceRaw = trip.source.rawValue
        excludedFromStats = trip.excludedFromStats
        pointsBlob = try JSONEncoder().encode(trip.points)
        stopEventsBlob = try JSONEncoder().encode(trip.stopEvents)
    }

    func trip() throws -> Trip {
        guard let points = try? JSONDecoder().decode([TrackPoint].self, from: pointsBlob) else {
            throw StoreMappingError.corruptBlob("TripRecord.pointsBlob \(id)")
        }
        guard let stopEvents = try? JSONDecoder().decode([StopEvent].self, from: stopEventsBlob) else {
            throw StoreMappingError.corruptBlob("TripRecord.stopEventsBlob \(id)")
        }
        return Trip(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            timezoneID: timezoneID,
            points: points,
            originPlaceID: originPlaceID,
            destinationPlaceID: destinationPlaceID,
            variantID: variantID,
            distanceM: distanceM,
            movingTime: movingTime,
            idleTime: idleTime,
            stopEvents: stopEvents,
            snapshotID: snapshotID,
            followedPlan: followedPlan,
            altSnapshotID: altSnapshotID,
            followedAltPlan: followedAltPlan,
            source: Trip.Source(rawValue: sourceRaw) ?? .auto,
            excludedFromStats: excludedFromStats
        )
    }
}

public extension PlaceRecord {
    convenience init(_ place: Place) {
        self.init()
        update(from: place)
    }

    func update(from place: Place) {
        id = place.id
        name = place.name
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        radiusM = place.radiusM
        kindRaw = place.kind.rawValue
        address = place.address
        createdAt = place.createdAt
    }

    func place() -> Place {
        Place(
            id: id,
            name: name,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            radiusM: radiusM,
            kind: Place.Kind(rawValue: kindRaw) ?? .custom,
            address: address,
            createdAt: createdAt
        )
    }
}

public extension VariantRecord {
    convenience init(_ variant: RouteVariant) {
        self.init()
        update(from: variant)
    }

    func update(from variant: RouteVariant) {
        id = variant.id
        originPlaceID = variant.originPlaceID
        destinationPlaceID = variant.destinationPlaceID
        polylineEncoded = variant.representativePolyline.encoded()
        autoName = variant.autoName
        customName = variant.customName
        tripCount = variant.tripCount
        signalCount = variant.intersections?.signalCount
        stopSignCount = variant.intersections?.stopSignCount
        coverageRaw = variant.intersections?.coverageConfidence.rawValue
        inventoryFetchedAt = variant.intersections?.fetchedAt
    }

    func variant() throws -> RouteVariant {
        guard let origin = originPlaceID, let destination = destinationPlaceID,
              let polyline = Polyline.decode(polylineEncoded)
        else {
            throw StoreMappingError.corruptPolyline("VariantRecord \(id)")
        }
        var inventory: IntersectionInventory?
        if let signalCount, let stopSignCount, let coverageRaw, let inventoryFetchedAt,
           let coverage = IntersectionInventory.CoverageConfidence(rawValue: coverageRaw) {
            inventory = IntersectionInventory(
                signalCount: signalCount,
                stopSignCount: stopSignCount,
                coverageConfidence: coverage,
                fetchedAt: inventoryFetchedAt
            )
        }
        return RouteVariant(
            id: id,
            originPlaceID: origin,
            destinationPlaceID: destination,
            representativePolyline: polyline,
            autoName: autoName,
            customName: customName,
            tripCount: tripCount,
            intersections: inventory
        )
    }
}

public extension SnapshotRecord {
    convenience init(_ snapshot: PlanSnapshot) throws {
        self.init()
        try update(from: snapshot)
    }

    func update(from snapshot: PlanSnapshot) throws {
        id = snapshot.id
        providerRaw = snapshot.provider.rawValue
        requestedAt = snapshot.requestedAt
        destinationPlaceID = snapshot.destinationPlaceID
        polylineEncoded = snapshot.polyline.encoded()
        distanceM = snapshot.distanceM
        staticDuration = snapshot.staticDuration
        trafficDuration = snapshot.trafficDuration
        alternatesBlob = try JSONEncoder().encode(snapshot.alternates)
    }

    func snapshot() throws -> PlanSnapshot {
        guard let polyline = Polyline.decode(polylineEncoded) else {
            throw StoreMappingError.corruptPolyline("SnapshotRecord \(id)")
        }
        guard let alternates = try? JSONDecoder().decode([PlanSnapshot.AltRoute].self, from: alternatesBlob) else {
            throw StoreMappingError.corruptBlob("SnapshotRecord.alternatesBlob \(id)")
        }
        return PlanSnapshot(
            id: id,
            provider: PlanSnapshot.Provider(rawValue: providerRaw) ?? .googleRoutes,
            requestedAt: requestedAt,
            destinationPlaceID: destinationPlaceID,
            polyline: polyline,
            distanceM: distanceM,
            staticDuration: staticDuration,
            trafficDuration: trafficDuration,
            alternates: alternates
        )
    }
}
