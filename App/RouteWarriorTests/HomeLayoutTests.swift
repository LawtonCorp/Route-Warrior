import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-045/D-046: never two ways to start a drive on one screen, and the
/// recorder takes space only while it is doing something. D-061 moved
/// its line beneath Go, where it discloses what Go does.
final class HomeLayoutTests: XCTestCase {
    private let states: [TripRecorder.State] = [.idle, .armed, .recording, .paused]

    /// D-069: a paused drive is still a drive. Nothing that would start
    /// a second one may appear while one is waiting to be resumed.
    func testAPausedDriveCountsAsADriveInProgress() {
        XCTAssertTrue(HomeLayout.driveInProgress(.paused))
        XCTAssertTrue(HomeLayout.driveInProgress(.recording))
        XCTAssertFalse(HomeLayout.driveInProgress(.armed))
        XCTAssertFalse(HomeLayout.driveInProgress(.idle))

        XCTAssertFalse(HomeLayout.showsRecordButton(hasDestination: false, state: .paused))
        XCTAssertFalse(HomeLayout.showsGoButton(hasDestination: true, state: .paused))
        // It carries the play and Stop buttons, so it keeps its own card.
        XCTAssertEqual(HomeLayout.recorderSlot(state: .paused, showsGo: false), .ownCard)
        XCTAssertEqual(HomeLayout.recorderSlot(state: .paused, showsGo: true), .ownCard)
    }

    func testThePausedCaptionSaysNothingIsBeingRecorded() {
        let caption = HomeLayout.recorderCaption(.paused)
        XCTAssertTrue(caption.hasPrefix("Paused"))
        XCTAssertTrue(caption.contains("nothing is being recorded"))
        XCTAssertNotEqual(caption, HomeLayout.recorderCaption(.recording))
    }

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

/// D-063/D-066: the route list is a list of choices, not a leaderboard
/// that re-sorts itself. The provider's rows keep the provider's order
/// and numbers; the driver's own routes sit ahead of them; a pick marks
/// a row and never moves one.
final class PlanListTests: XCTestCase {
    private let line = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
    ])

    private func snapshot(alternates: [TimeInterval]) -> PlanSnapshot {
        var plan = PlanSnapshot(
            provider: .googleRoutes, requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            polyline: line, distanceM: 2_224, staticDuration: 600, trafficDuration: 600
        )
        plan.alternates = alternates.map {
            PlanSnapshot.AltRoute(polyline: line, staticDuration: $0, trafficDuration: $0)
        }
        return plan
    }

    private func personal(_ id: UUID, name: String, minutes: Double, claim: String? = nil) -> PersonalRoutes.Row {
        PersonalRoutes.Row(
            id: id, name: name, polyline: line, usualDuration: minutes * 60,
            drivesCounted: 7, tier: .dayClassSlot, claim: claim
        )
    }

    func testTheProviderRowsAreItsOrderWithItsOwnNumbers() {
        let rows = PlanList.rows(snapshot(alternates: [400, 800]))
        XCTAssertEqual(rows.map(\.id), [.route(0), .route(1), .route(2)])
        XCTAssertEqual(rows.map(\.title), ["Google's plan", "Alternate 1", "Alternate 2"])
        XCTAssertEqual(rows.map(\.eta), [600, 400, 800])
        XCTAssertTrue(rows.allSatisfy { !$0.isPersonal && $0.caption == nil })
    }

    func testAPlanWithNoAlternatesIsStillOneRow() {
        XCTAssertEqual(PlanList.rows(snapshot(alternates: [])).map(\.title), ["Google's plan"])
    }

    /// A personal row says whose it is, what it usually takes, and what
    /// that number rests on.
    func testPersonalRowsCarryTheirClaimAndTheirEvidence() {
        let maple = UUID()
        let rows = PlanList.rows(personal: [
            personal(maple, name: "via Maple Ave", minutes: 18, claim: "usually fastest on weekday mornings"),
            personal(UUID(), name: "the back way", minutes: 20),
        ])
        XCTAssertEqual(rows[0].id, .personal(maple))
        XCTAssertEqual(rows[0].title, "Your way — via Maple Ave")
        XCTAssertEqual(rows[0].eta, 1_080)
        XCTAssertEqual(rows[0].caption, "usually fastest on weekday mornings · 7 drives")
        XCTAssertEqual(rows[1].caption, "7 drives", "no claim, just the evidence")
        XCTAssertTrue(rows.allSatisfy(\.isPersonal))
    }

    /// A provider pick decides what the drive departs with (D-010,
    /// FR-20). A personal pick decides nothing here: the provider's plan
    /// stays the baseline (D-066).
    func testTheDepartureSnapshotCarriesAProviderPickAndIgnoresAPersonalOne() {
        let plan = snapshot(alternates: [400, 800])
        XCTAssertEqual(PlanList.departure(plan, selecting: .route(0)), plan)
        XCTAssertEqual(PlanList.departure(plan, selecting: .route(1)).trafficDuration, 400)
        XCTAssertEqual(PlanList.departure(plan, selecting: .route(2)).trafficDuration, 800)
        XCTAssertEqual(PlanList.departure(plan, selecting: .route(2)).id, plan.id)
        XCTAssertEqual(PlanList.departure(plan, selecting: .personal(UUID())), plan, "the baseline does not move")
    }

    /// Applied to the snapshot as it came back, every time — so the same
    /// pick always means the same route, however often it is made.
    func testThePickIsAlwaysReadAgainstTheOriginalList() {
        let plan = snapshot(alternates: [400, 800])
        for row in [1, 2, 1, 2, 2] {
            XCTAssertEqual(
                PlanList.departure(plan, selecting: .route(row)).trafficDuration,
                row == 1 ? 400 : 800, "row \(row)"
            )
        }
    }

    func testAPickThatNamesNothingFallsBackToTheRecommendation() {
        let plan = snapshot(alternates: [400])
        let mine = UUID()
        let routes = [personal(mine, name: "mine", minutes: 18)]
        XCTAssertEqual(PlanList.departure(plan, selecting: .route(9)), plan)
        XCTAssertEqual(PlanList.clamped(.route(9), to: plan, personal: routes), .route(0))
        XCTAssertEqual(PlanList.clamped(.route(1), to: plan, personal: routes), .route(1))
        XCTAssertEqual(PlanList.clamped(.route(1), to: nil, personal: routes), .route(0))
        XCTAssertEqual(PlanList.clamped(.personal(mine), to: nil, personal: routes), .personal(mine))
        XCTAssertEqual(PlanList.clamped(.personal(UUID()), to: plan, personal: routes), .route(0))
    }
}
