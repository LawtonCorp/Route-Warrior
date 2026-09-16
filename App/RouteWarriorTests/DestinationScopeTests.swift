import RouteWarriorKit
import RouteWarriorStore
import XCTest
@testable import RouteWarrior

/// D-076: the Destination screen answers for one starting point at a
/// time. A drive home from the corner shop and a drive home from across
/// town are different journeys; pooling them produced a fastest route
/// that meant nothing and a heatmap cell that said an hour because one
/// long drive landed in it.
final class DestinationScopeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let home = UUID()

    private func place(_ name: String, id: UUID) -> PlaceRecord {
        let record = PlaceRecord(Place(name: name, coordinate: Coordinate(latitude: 0, longitude: 0)))
        record.id = id
        return record
    }

    private func trip(from origin: UUID?, minutes: Double = 10, day: Double = 0) -> Trip {
        let start = t0.addingTimeInterval(day * 86_400)
        return Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            timezoneID: "America/Chicago",
            points: [],
            originPlaceID: origin,
            destinationPlaceID: home
        )
    }

    private func variant(from origin: UUID) -> RouteVariant {
        RouteVariant(
            originPlaceID: origin,
            destinationPlaceID: home,
            representativePolyline: Polyline(coordinates: [
                Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.01),
            ])
        )
    }

    // MARK: Which starting points exist

    func testOriginsAreMostDrivenFirst() {
        let work = UUID(), gym = UUID()
        let places = [place("Work", id: work), place("The gym", id: gym)]
        let trips = [trip(from: gym), trip(from: work), trip(from: work), trip(from: work)]

        let origins = DestinationScope.origins(for: trips, places: places)
        XCTAssertEqual(origins.map(\.name), ["Work", "The gym"])
        XCTAssertEqual(origins.map(\.drives), [3, 1])
    }

    /// Ties break by name so the picker never reorders under the driver
    /// between one drive and the next.
    func testATieBreaksByNameRatherThanArbitrarily() {
        let a = UUID(), b = UUID()
        let places = [place("Zoo", id: a), place("Airport", id: b)]
        let origins = DestinationScope.origins(for: [trip(from: a), trip(from: b)], places: places)
        XCTAssertEqual(origins.map(\.name), ["Airport", "Zoo"])
    }

    /// A drive that began somewhere unsaved belongs to no starting point.
    /// It is counted under "all" and nowhere else, and the screen says so.
    func testDrivesFromUnsavedPlacesBelongToNoStartingPoint() {
        let work = UUID()
        let places = [place("Work", id: work)]
        let trips = [trip(from: work), trip(from: nil), trip(from: UUID())]

        let origins = DestinationScope.origins(for: trips, places: places)
        XCTAssertEqual(origins.map(\.name), ["Work"])
        XCTAssertEqual(origins.map(\.drives), [1])
        XCTAssertEqual(DestinationScope.trips(trips, in: .all).count, 3)
        XCTAssertEqual(DestinationScope.trips(trips, in: .origin(work)).count, 1)
    }

    // MARK: What the screen opens on

    func testItOpensOnTheStartingPointDrivenFromMost() {
        let work = UUID(), gym = UUID()
        let places = [place("Work", id: work), place("The gym", id: gym)]
        let origins = DestinationScope.origins(
            for: [trip(from: gym), trip(from: work), trip(from: work)], places: places
        )
        XCTAssertEqual(DestinationScope.defaultSelection(for: origins), .origin(work))
        XCTAssertTrue(DestinationScope.showsPicker(for: origins))
    }

    /// One starting point needs no scoping, and the picker would be
    /// furniture — most destinations are driven to from one place.
    func testOneStartingPointNeedsNoPicker() {
        let work = UUID()
        let places = [place("Work", id: work)]
        let origins = DestinationScope.origins(for: [trip(from: work)], places: places)
        XCTAssertEqual(DestinationScope.defaultSelection(for: origins), .all)
        XCTAssertFalse(DestinationScope.showsPicker(for: origins))
        XCTAssertFalse(DestinationScope.showsPicker(for: []))
    }

    /// D-062's rule: a stored choice the data can no longer honour falls
    /// back rather than being acted on. Deleting Work must not leave the
    /// screen scoped to a starting point with nothing in it.
    func testAScopeTheDataCannotHonourFallsBackToAll() {
        let work = UUID(), gym = UUID()
        let places = [place("The gym", id: gym)]
        let origins = DestinationScope.origins(for: [trip(from: gym)], places: places)

        XCTAssertEqual(DestinationScope.resolved(.origin(work), in: origins), .all)
        XCTAssertEqual(DestinationScope.resolved(.origin(gym), in: origins), .origin(gym))
        XCTAssertEqual(DestinationScope.resolved(.all, in: origins), .all)
    }

    // MARK: What a scope may claim

    /// The whole point: routes are only raced within one starting point.
    func testOnlyOneStartingPointMayCompareRoutes() {
        XCTAssertFalse(DestinationScope.Selection.all.comparesRoutes)
        XCTAssertTrue(DestinationScope.Selection.origin(UUID()).comparesRoutes)
    }

    func testScopingKeepsOnlyTheRoutesThatStartThere() {
        let work = UUID(), gym = UUID()
        let variants = [variant(from: work), variant(from: gym), variant(from: work)]

        XCTAssertEqual(DestinationScope.variants(variants, in: .all).count, 3)
        let fromWork = DestinationScope.variants(variants, in: .origin(work))
        XCTAssertEqual(fromWork.count, 2)
        XCTAssertTrue(fromWork.allSatisfy { $0.originPlaceID == work })
    }

    // MARK: The cheap paths answer the same way (D-077)

    /// The screen builds its picker from stored columns rather than
    /// decoded drives. The two entry points must not drift: a starting
    /// point counted from `originPlaceID` is the same starting point.
    func testCountingFromColumnsMatchesCountingFromDrives() {
        let work = UUID(), gym = UUID()
        let places = [place("Work", id: work), place("The gym", id: gym)]
        let trips = [trip(from: work), trip(from: gym), trip(from: work), trip(from: nil)]

        let fromDrives = DestinationScope.origins(for: trips, places: places)
        let fromColumns = DestinationScope.origins(
            countingOriginsOf: trips.map(\.originPlaceID), places: places
        )
        XCTAssertEqual(fromDrives, fromColumns)
        XCTAssertEqual(fromColumns.map(\.drives), [2, 1])
    }

    /// Narrowing before decoding must keep exactly the drives that
    /// filtering after decoding would have kept.
    func testAdmittingFromAColumnMatchesFilteringTheDrives() {
        let work = UUID(), gym = UUID()
        let trips = [trip(from: work), trip(from: gym), trip(from: nil)]

        for selection in [DestinationScope.Selection.all, .origin(work), .origin(gym)] {
            let byRule = DestinationScope.trips(trips, in: selection)
            let byColumn = trips.filter {
                DestinationScope.admits(originPlaceID: $0.originPlaceID, in: selection)
            }
            XCTAssertEqual(byRule.count, byColumn.count, "\(selection)")
        }
    }

    // MARK: The words

    func testTheFooterSaysWhatIsCountedAndWhatIsLeftOut() {
        let all = DestinationScopeText.footer(scope: .all, destination: "Home", unscopedDrives: 0)
        XCTAssertTrue(all.contains("from anywhere"))
        XCTAssertTrue(all.contains("not compared across starting points"))

        let scoped = DestinationScopeText.footer(
            scope: .origin(UUID()), destination: "Home", unscopedDrives: 3
        )
        XCTAssertTrue(scoped.contains("different journeys"))
        XCTAssertTrue(scoped.contains("3 other drives"), "the drives left out are counted, not hidden")

        let nothingLeftOut = DestinationScopeText.footer(
            scope: .origin(UUID()), destination: "Home", unscopedDrives: 0
        )
        XCTAssertFalse(nothingLeftOut.contains("other drive"))
    }

    func testTheRoutesFooterOnlyExplainsMixedOriginsWhenTheyAreMixed() {
        let all = DestinationScopeText.routesFooter(scope: .all, destination: "Home")
        XCTAssertTrue(all.contains("do not all start in the same place"))
        let scoped = DestinationScopeText.routesFooter(scope: .origin(UUID()), destination: "Home")
        XCTAssertFalse(scoped.contains("do not all start"))
        XCTAssertTrue(scoped.contains("coloured to match"))
    }

    func testTheMissingRaceExplainsItself() {
        XCTAssertTrue(DestinationScopeText.noRaceAcrossOrigins.contains("different places"))
        XCTAssertTrue(DestinationScopeText.noRaceAcrossOrigins.contains("Pick one starting point"))
    }
}
