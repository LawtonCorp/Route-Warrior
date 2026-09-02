import RouteWarriorKit
import RouteWarriorStore
import XCTest

@testable import RouteWarrior

/// D-018: colour carries meaning, so the meaning-to-colour mappings are
/// plain functions with tests. A row tinted green for a trip that lost to
/// Google's ETA would be a lie the eye believes before the numbers load.
final class ThemeTests: XCTestCase {
    func testTripToneFollowsTheEtaDelta() {
        XCTAssertEqual(TripTone.forTrip(deltaSeconds: -30, excluded: false), .faster)
        XCTAssertEqual(TripTone.forTrip(deltaSeconds: 0, excluded: false), .faster)
        XCTAssertEqual(TripTone.forTrip(deltaSeconds: 30, excluded: false), .slower)
        XCTAssertEqual(TripTone.forTrip(deltaSeconds: nil, excluded: false), .noComparison)
        // A passenger ride is never a win or a loss, whatever the delta.
        XCTAssertEqual(TripTone.forTrip(deltaSeconds: -30, excluded: true), .excluded)
        XCTAssertEqual(TripTone.forTrip(deltaSeconds: nil, excluded: true), .excluded)
    }

    func testWinAndLossAreVisuallyDistinct() {
        XCTAssertNotEqual(TripTone.faster.color, TripTone.slower.color)
        XCTAssertNotEqual(TripTone.faster.symbol, TripTone.slower.symbol)
    }

    func testEveryPlaceKindHasItsOwnGlyphAndColour() {
        let symbols = Place.Kind.allCases.map(\.symbol)
        let colours = Place.Kind.allCases.map(\.color)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertEqual(Set(colours).count, colours.count)
    }

    func testRecorderStatesAreVisuallyDistinct() {
        let states: [TripRecorder.State] = [.idle, .armed, .recording]
        XCTAssertEqual(Set(states.map(Theme.statusTint(for:))).count, states.count)
        XCTAssertEqual(Set(states.map(Theme.statusSymbol(for:))).count, states.count)
    }

    func testRowDeltaMatchesTheDetailScreen() {
        let trip = TripRecord()
        trip.startedAt = Date(timeIntervalSince1970: 0)
        trip.endedAt = Date(timeIntervalSince1970: 600)
        let snapshot = SnapshotRecord()
        snapshot.trafficDuration = 540
        trip.snapshotID = snapshot.id
        // 10:00 driven against a 9:00 ETA: one minute behind the plan.
        XCTAssertEqual(trip.etaDeltaSeconds(in: [snapshot]), 60)
        // No snapshot attached, or the attached snapshot missing, is "no
        // comparison" — never a delta against the wrong plan.
        XCTAssertNil(TripRecord().etaDeltaSeconds(in: [snapshot]))
        XCTAssertNil(trip.etaDeltaSeconds(in: []))
    }
}
