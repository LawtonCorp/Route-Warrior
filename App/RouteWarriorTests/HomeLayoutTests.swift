import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-045/D-046: never two ways to start a drive on one screen, and the
/// recorder takes space only while it is doing something. D-061 moved
/// its line beneath Go, where it discloses what Go does.
final class HomeLayoutTests: XCTestCase {
    private let states: [TripRecorder.State] = [.idle, .armed, .recording]

    func testRecordShowsOnlyWhenNothingElseWouldStartADrive() {
        XCTAssertTrue(HomeLayout.showsRecordButton(hasDestination: false, state: .idle))
        XCTAssertTrue(HomeLayout.showsRecordButton(hasDestination: false, state: .armed))
        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: true, state: .idle))
        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: false, state: .recording))
        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: true, state: .recording))
    }

    func testGoNeedsSomewhereToGoAndADriveNotAlreadyRunning() {
        XCTAssertTrue(HomeLayout.showsGoButton(hasDestination: true, state: .idle))
        XCTAssertTrue(HomeLayout.showsGoButton(hasDestination: true, state: .armed))
        XCTAssertFalse(HomeLayout.showsGoButton(hasDestination: true, state: .recording))
        XCTAssertFalse(HomeLayout.showsGoButton(hasDestination: false, state: .armed))
    }

    /// Record and Go are the two ways to start a drive; D-045 says never
    /// both at once.
    func testRecordAndGoAreNeverBothOffered() {
        for state in states {
            for hasDestination in [true, false] {
                let both = HomeLayout.showsRecordButton(hasDestination: hasDestination, state: state)
                    && HomeLayout.showsGoButton(hasDestination: hasDestination, state: state)
                XCTAssertFalse(both, "\(state), destination: \(hasDestination)")
            }
        }
    }

    // MARK: Where the recorder's line sits (D-061)

    func testTheRecorderIsSilentWhenIdleWithNothingToExplain() {
        XCTAssertEqual(HomeLayout.recorderSlot(state: .idle, showsGo: false), .hidden)
    }

    func testADetectedDriveSitsUnderGoWhenThereIsOneAndKeepsItsCardOtherwise() {
        XCTAssertEqual(HomeLayout.recorderSlot(state: .armed, showsGo: true), .underGo)
        XCTAssertEqual(HomeLayout.recorderSlot(state: .armed, showsGo: false), .ownCard)
    }

    /// The recording line carries Stop and the drive view, so it keeps a
    /// card of its own — and Go is never on screen beside it anyway.
    func testRecordingAlwaysKeepsItsOwnCard() {
        XCTAssertEqual(HomeLayout.recorderSlot(state: .recording, showsGo: false), .ownCard)
        XCTAssertEqual(HomeLayout.recorderSlot(state: .recording, showsGo: true), .ownCard)
    }

    /// The explanation of Go is reachable on every screen that shows Go,
    /// whether or not a drive has been detected — and never claims a
    /// place under a button that is not there.
    func testTheLineIsUnderGoExactlyWhenGoIsOnTheScreen() {
        for state in states {
            for hasDestination in [true, false] {
                let showsGo = HomeLayout.showsGoButton(hasDestination: hasDestination, state: state)
                let slot = HomeLayout.recorderSlot(state: state, showsGo: showsGo)
                XCTAssertEqual(slot == .underGo, showsGo, "\(state), destination: \(hasDestination)")
            }
        }
    }

    // MARK: The words

    func testTheArmedCaptionSaysWhatItMeansForTheDriver() {
        // D-056: no mechanism talk; the driver has nothing to do.
        XCTAssertEqual(HomeLayout.recorderCaption(.recording), "Rec")
        let armed = HomeLayout.recorderCaption(.armed)
        XCTAssertTrue(armed.hasPrefix("Drive detected"))
        XCTAssertTrue(armed.contains("on its own"))
        XCTAssertFalse(armed.lowercased().contains("confirming"))
    }

    /// Under Go, a detected drive still speaks for itself; without one
    /// the line offers the explanation rather than inventing a drive.
    func testTheLineUnderGoNamesADetectedDriveOrTheExplanationItHides() {
        XCTAssertEqual(HomeLayout.goNoteTitle(.armed), HomeLayout.recorderCaption(.armed))
        let idle = HomeLayout.goNoteTitle(.idle)
        XCTAssertTrue(idle.contains("Go"))
        XCTAssertFalse(idle.contains("Drive detected"), "nothing has been detected")
    }
}
