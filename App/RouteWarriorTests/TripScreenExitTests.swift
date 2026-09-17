import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-080: deleting a drive from its own screen crashed the app. The
/// screen was deleting the record it is built from and *then* closing,
/// so the next read of that record — the navigation title reads
/// `record.label` — touched a deleted `@Model`, which traps.
@MainActor
final class TripScreenExitTests: XCTestCase {
    func testTheOrdinaryExitSavesTheLabel() {
        XCTAssertEqual(TripScreenExit.onDisappear(deleting: false), .commitLabel)
    }

    /// Writing the driver's label to a record that is being deleted is
    /// the same invalid access by another route.
    func testAnExitThatIsADeleteDoesNotWriteToTheRecord() {
        XCTAssertEqual(TripScreenExit.onDisappear(deleting: true), .delete)
    }

    // MARK: The deletion itself still does its job

    /// The ordering fix must not have changed what a delete takes with
    /// it (D-058): the trip, the snapshots no other trip refers to, and
    /// a tick off its route's drive count.
    func testDeletingStillRemovesTheTripAndItsOrphanedSnapshot() throws {
        let context = ModelContext(try RouteWarriorStoreFactory.inMemoryContainer())
        let snapshotID = UUID()
        let variant = VariantRecord()
        variant.tripCount = 2
        context.insert(variant)

        let record = TripRecord()
        record.snapshotID = snapshotID
        record.variantID = variant.id
        context.insert(record)

        let snapshot = SnapshotRecord()
        snapshot.id = snapshotID
        context.insert(snapshot)
        try context.save()

        TripDeletion.delete(record, in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<TripRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SnapshotRecord>()).isEmpty,
                      "no trip refers to that departure snapshot any more")
        XCTAssertTrue(try context.fetch(FetchDescriptor<VariantRecord>()).isEmpty,
                      "that was the route's last drive")
    }
}
