import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-074: the driver arranges their places by dragging, and that order is
/// load-bearing — the free tier analyses the first few destinations *by
/// position*, so the arrangement decides which places fall inside the
/// allowance. These cover the rule and the store wiring that serves it.
@MainActor
final class PlaceOrderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    func testDraggingARowDownPutsItAfterTheRowItPassed() {
        let list = ids(4)
        let moved = PlaceOrder.reordered(list, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(moved, [list[1], list[2], list[0], list[3]])
    }

    func testDraggingARowUpPutsItBeforeTheRowItPassed() {
        let list = ids(4)
        let moved = PlaceOrder.reordered(list, from: IndexSet(integer: 3), to: 1)
        XCTAssertEqual(moved, [list[0], list[3], list[1], list[2]])
    }

    func testMovingSeveralRowsKeepsTheirOrderAmongThemselves() {
        let list = ids(5)
        let moved = PlaceOrder.reordered(list, from: IndexSet([0, 2]), to: 5)
        XCTAssertEqual(moved, [list[1], list[3], list[4], list[0], list[2]])
    }

    /// The invariant the caller depends on: every place ends up carrying
    /// its own row number, with no gaps and no ties, so a later save
    /// cannot land in the middle of the list.
    func testEveryPositionIsWrittenBackWithoutGapsOrTies() {
        let list = ids(6)
        let moved = PlaceOrder.reordered(list, from: IndexSet(integer: 5), to: 0)
        let indices = moved.enumerated().map(\.offset)
        XCTAssertEqual(indices, Array(0..<6))
        XCTAssertEqual(Set(moved).count, 6, "no place is lost or duplicated by a drag")
    }

    func testANewPlaceGoesAfterEverythingAlreadyThere() {
        XCTAssertEqual(PlaceOrder.nextIndex(after: []), 0)
        // Places saved before the list could be reordered all tie at zero.
        XCTAssertEqual(PlaceOrder.nextIndex(after: [0, 0, 0]), 1)
        XCTAssertEqual(PlaceOrder.nextIndex(after: [0, 1, 2]), 3)
        // A delete leaves a gap; a new place still goes last, not into it.
        XCTAssertEqual(PlaceOrder.nextIndex(after: [0, 5]), 6)
    }

    // MARK: The store actually sorts this way

    private func insert(
        _ context: ModelContext, name: String, created: TimeInterval, sortIndex: Int = 0
    ) {
        let record = PlaceRecord(Place(
            name: name,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            createdAt: t0.addingTimeInterval(created)
        ))
        record.sortIndex = sortIndex
        context.insert(record)
    }

    /// Nobody has dragged anything yet, so every place ties at zero and
    /// the list is the one drivers already had: oldest first.
    func testPlacesNobodyHasMovedKeepTheirOldestFirstOrder() throws {
        let context = ModelContext(try RouteWarriorStoreFactory.inMemoryContainer())
        insert(context, name: "Work", created: 200)
        insert(context, name: "Home", created: 100)
        insert(context, name: "School", created: 300)
        try context.save()

        let fetched = try context.fetch(PlaceOrder.fetchDescriptor)
        XCTAssertEqual(fetched.map(\.name), ["Home", "Work", "School"])
    }

    func testAFullyArrangedListComesBackInThatArrangement() throws {
        let context = ModelContext(try RouteWarriorStoreFactory.inMemoryContainer())
        insert(context, name: "Work", created: 100, sortIndex: 2)
        insert(context, name: "Home", created: 200, sortIndex: 0)
        insert(context, name: "School", created: 300, sortIndex: 1)
        try context.save()

        let fetched = try context.fetch(PlaceOrder.fetchDescriptor)
        XCTAssertEqual(fetched.map(\.name), ["Home", "School", "Work"],
                       "the arrangement wins over when each place was saved")
    }

    /// D-060's lesson, applied to the arrangement: it lives on the record,
    /// not on the kit's `Place`, so rewriting a record from a kit value
    /// cannot drag a place back to where it started.
    func testAPlaceKeepsItsPositionWhenItsRecordIsRewritten() {
        let place = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
        let record = PlaceRecord(place)
        record.sortIndex = 4

        var renamed = place
        renamed.name = "Home (new address)"
        record.update(from: renamed)

        XCTAssertEqual(record.name, "Home (new address)")
        XCTAssertEqual(record.sortIndex, 4)
    }
}
