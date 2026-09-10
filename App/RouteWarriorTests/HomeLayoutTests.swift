import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-045/D-046: never two ways to start a drive on one screen, and the
/// recorder takes space only while it is doing something.
final class HomeLayoutTests: XCTestCase {
    func testRecordShowsOnlyWhenNothingElseWouldStartADrive() {
        XCTAssertTrue(HomeLayout.showsRecordButton(hasDestination: false, state: .idle))
        XCTAssertTrue(HomeLayout.showsRecordButton(hasDestination: false, state: .armed))
        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: true, state: .idle))
        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: false, state: .recording))
        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: true, state: .recording))
    }

    func testTheRecorderRowIsSilentWhenIdle() {
        XCTAssertFalse(HomeLayout.showsRecorderRow(.idle))
        XCTAssertTrue(HomeLayout.showsRecorderRow(.armed))
        XCTAssertTrue(HomeLayout.showsRecorderRow(.recording))
    }

    func testTheArmedCaptionSaysWhatItMeansForTheDriver() {
        // D-056: no mechanism talk; the driver has nothing to do.
        XCTAssertEqual(HomeLayout.recorderCaption(.recording), "Rec")
        let armed = HomeLayout.recorderCaption(.armed)
        XCTAssertTrue(armed.hasPrefix("Drive detected"))
        XCTAssertTrue(armed.contains("on its own"))
        XCTAssertFalse(armed.lowercased().contains("confirming"))
    }
}
