import XCTest
@testable import RouteWarrior

/// D-059: a following camera stands down when the driver moves the map
/// and comes back on Recenter. The Recenter button exists only while
/// there is something to recenter.
@MainActor
final class MapFollowTests: XCTestCase {
    func testAGestureStopsTheChaseAndRecenterResumesIt() {
        let follow = MapFollowState()
        XCTAssertTrue(follow.isFollowing, "the drive view starts on the car")
        XCTAssertTrue(follow.drivesCamera(for: .followUser))

        follow.userMovedMap()
        XCTAssertFalse(follow.isFollowing)
        XCTAssertFalse(follow.drivesCamera(for: .followUser), "the pan survives the next GPS fix")

        follow.recenter()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertTrue(follow.drivesCamera(for: .followUser))
    }

    func testAFitToContentMapIsAlwaysTheDriversToMove() {
        // The Plan tab and the trip detail frame their content once and
        // never chase, so nothing there is ever suspended or recentred.
        let follow = MapFollowState()
        follow.userMovedMap()
        XCTAssertTrue(follow.drivesCamera(for: .fitContent))
        XCTAssertFalse(follow.showsRecenter(for: .fitContent))
    }

    func testTheButtonAppearsOnlyOnceTheMapHasBeenMoved() {
        let follow = MapFollowState()
        XCTAssertFalse(follow.showsRecenter(for: .followUser), "nothing to recenter while centred")
        follow.userMovedMap()
        XCTAssertTrue(follow.showsRecenter(for: .followUser))
        follow.recenter()
        XCTAssertFalse(follow.showsRecenter(for: .followUser))
    }
}
