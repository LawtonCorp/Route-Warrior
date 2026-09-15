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

/// D-063: the route list is a list of choices, not a leaderboard that
/// re-sorts itself. Row 0 is the provider's recommendation; the rest
/// keep the numbers the provider gave them, whatever is picked.
final class PlanListTests: XCTestCase {
    private func snapshot(alternates: [TimeInterval]) -> PlanSnapshot {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
        ])
        var plan = PlanSnapshot(
            provider: .googleRoutes, requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            polyline: line, distanceM: 2_224, staticDuration: 600, trafficDuration: 600
        )
        plan.alternates = alternates.map {
            PlanSnapshot.AltRoute(polyline: line, staticDuration: $0, trafficDuration: $0)
        }
        return plan
    }

    func testTheRowsAreTheProvidersOrderWithItsOwnNumbers() {
        let rows = PlanList.rows(snapshot(alternates: [400, 800]))
        XCTAssertEqual(rows.map(\.id), [0, 1, 2])
        XCTAssertEqual(rows.map(\.title), ["Google's plan", "Alternate 1", "Alternate 2"])
        XCTAssertEqual(rows.map(\.eta), [600, 400, 800])
    }

    func testAPlanWithNoAlternatesIsStillOneRow() {
        XCTAssertEqual(PlanList.rows(snapshot(alternates: [])).map(\.title), ["Google's plan"])
    }

    /// The pick decides what the drive departs with (D-010, FR-20) —
    /// it just does not decide what the list looks like.
    func testTheDepartureSnapshotCarriesThePickedRoute() {
        let plan = snapshot(alternates: [400, 800])
        XCTAssertEqual(PlanList.departure(plan, selecting: 0), plan, "the recommendation is the snapshot itself")
        XCTAssertEqual(PlanList.departure(plan, selecting: 1).trafficDuration, 400)
        XCTAssertEqual(PlanList.departure(plan, selecting: 2).trafficDuration, 800)
        // Still this departure's snapshot from this provider.
        XCTAssertEqual(PlanList.departure(plan, selecting: 2).id, plan.id)
        XCTAssertEqual(PlanList.departure(plan, selecting: 2).provider, plan.provider)
    }

    /// Applied to the snapshot as it came back, every time — so the same
    /// pick always means the same route, however often it is made.
    func testThePickIsAlwaysReadAgainstTheOriginalList() {
        let plan = snapshot(alternates: [400, 800])
        for row in [1, 2, 1, 2, 2] {
            XCTAssertEqual(
                PlanList.departure(plan, selecting: row).trafficDuration,
                row == 1 ? 400 : 800,
                "row \(row)"
            )
        }
    }

    func testARowThatIsNotThereFallsBackToTheRecommendation() {
        let plan = snapshot(alternates: [400])
        XCTAssertEqual(PlanList.departure(plan, selecting: 9), plan)
        XCTAssertEqual(PlanList.departure(plan, selecting: -1), plan)
        XCTAssertEqual(PlanList.clamped(9, to: plan), PlanList.recommendedRow)
        XCTAssertEqual(PlanList.clamped(1, to: plan), 1)
        XCTAssertEqual(PlanList.clamped(1, to: nil), PlanList.recommendedRow)
    }
}
