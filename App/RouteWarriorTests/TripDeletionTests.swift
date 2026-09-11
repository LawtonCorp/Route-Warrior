import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-058: a deleted trip takes with it the departure snapshots nothing
/// else refers to and one tick of its route's drive count, and the last
/// drive on a route takes the route too. Nothing a surviving trip still
/// needs is ever removed.
@MainActor
final class TripDeletionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: The rule

    func testTheSnapshotsGoUnlessAnotherTripStillUsesThem() {
        let shared = UUID()
        let mine = UUID()
        let trip = TripDeletion.Facts(id: UUID(), snapshotID: mine, altSnapshotID: shared)
        let other = TripDeletion.Facts(id: UUID(), snapshotID: shared)

        let plan = TripDeletion.plan(deleting: trip, others: [trip, other])
        XCTAssertEqual(plan.snapshotIDs, [mine], "the shared one stays for the trip that still needs it")

        let alone = TripDeletion.plan(deleting: trip, others: [trip])
        XCTAssertEqual(alone.snapshotIDs, [mine, shared])
    }

    func testTheRouteLosesOneDriveAndGoesWithItsLast() {
        let route = UUID()
        let trip = TripDeletion.Facts(id: UUID(), variantID: route)
        let sibling = TripDeletion.Facts(id: UUID(), variantID: route)

        let withSibling = TripDeletion.plan(deleting: trip, others: [trip, sibling])
        XCTAssertEqual(withSibling.variantID, route)
        XCTAssertFalse(withSibling.removesVariant)

        let last = TripDeletion.plan(deleting: trip, others: [trip])
        XCTAssertEqual(last.variantID, route)
        XCTAssertTrue(last.removesVariant)
    }

    func testATripWithNoPlanAndNoRouteTakesNothingWithIt() {
        let plan = TripDeletion.plan(deleting: TripDeletion.Facts(id: UUID()), others: [])
        XCTAssertEqual(plan, TripDeletion.Plan())
    }

    // MARK: The wiring

    private func trip(startedAt: Date, snapshot: UUID?, variant: UUID?) -> TripRecord {
        let record = TripRecord()
        record.startedAt = startedAt
        record.endedAt = startedAt.addingTimeInterval(600)
        record.snapshotID = snapshot
        record.variantID = variant
        return record
    }

    func testDeletingThroughTheStoreRemovesTheRightRowsAndKeepsTheRest() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)

        let route = UUID()
        let doomedSnapshot = UUID()
        let keptSnapshot = UUID()
        for id in [doomedSnapshot, keptSnapshot] {
            let snapshot = SnapshotRecord()
            snapshot.id = id
            snapshot.polylineEncoded = Polyline(coordinates: [
                Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.01),
            ]).encoded()
            context.insert(snapshot)
        }
        let variant = VariantRecord()
        variant.id = route
        variant.tripCount = 2
        context.insert(variant)

        let doomed = trip(startedAt: t0, snapshot: doomedSnapshot, variant: route)
        let survivor = trip(startedAt: t0.addingTimeInterval(3_600), snapshot: keptSnapshot, variant: route)
        context.insert(doomed)
        context.insert(survivor)
        try context.save()

        TripDeletion.delete(doomed, in: context)

        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(trips.map(\.id), [survivor.id])
        let snapshots = try context.fetch(FetchDescriptor<SnapshotRecord>())
        XCTAssertEqual(snapshots.map(\.id), [keptSnapshot], "the survivor's plan is untouched")
        let variants = try context.fetch(FetchDescriptor<VariantRecord>())
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants[0].tripCount, 1, "the route lost one drive, not itself")

        TripDeletion.delete(survivor, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TripRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SnapshotRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VariantRecord>()).isEmpty, "the last drive takes the route")
    }
}
