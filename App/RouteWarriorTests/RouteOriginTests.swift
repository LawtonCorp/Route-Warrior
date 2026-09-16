import RouteWarriorKit
import RouteWarriorStore
import XCTest
@testable import RouteWarrior

/// D-075: the Destination screen lists every route that *ends* here, from
/// anywhere, so each row says where it started. Three drives home from
/// three different places are three routes, and they are even named alike
/// — the auto-name counts routes within an origin→destination pair, and
/// this screen does not filter by origin.
final class RouteOriginTests: XCTestCase {
    private func place(_ name: String) -> PlaceRecord {
        PlaceRecord(Place(name: name, coordinate: Coordinate(latitude: 0, longitude: 0)))
    }

    func testARouteNamesTheSavedPlaceItStartsFrom() {
        let work = place("Work")
        let gym = place("The gym")
        let places = [work, gym]

        XCTAssertEqual(RouteOrigin.name(of: work.id, in: places), "Work")
        XCTAssertEqual(RouteOrigin.caption(of: work.id, in: places), "from Work")
        XCTAssertEqual(RouteOrigin.caption(of: gym.id, in: places), "from The gym")
    }

    /// A route outlives the place it started from: deleting Work must not
    /// leave a row claiming to start somewhere, or worse, crash looking
    /// for it.
    func testADeletedOriginSaysNothingRatherThanGuessing() {
        let places = [place("Work")]
        XCTAssertNil(RouteOrigin.name(of: UUID(), in: places))
        XCTAssertNil(RouteOrigin.caption(of: UUID(), in: places))
    }

    /// Routes recorded before the app knew where a drive began carry no
    /// origin at all.
    func testNoOriginSaysNothing() {
        XCTAssertNil(RouteOrigin.caption(of: nil, in: [place("Work")]))
        XCTAssertNil(RouteOrigin.caption(of: nil, in: []))
    }

    /// An unnamed place is not a name. Better to say nothing than "from ".
    func testAnEmptyNameIsNotAName() {
        let blank = place("")
        XCTAssertNil(RouteOrigin.name(of: blank.id, in: [blank]))
        XCTAssertNil(RouteOrigin.caption(of: blank.id, in: [blank]))
    }
}
