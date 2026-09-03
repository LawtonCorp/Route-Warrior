import RouteWarriorKit
import RouteWarriorStore
import SwiftUI
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

    func testEveryPlaceKindHasItsOwnGlyph() {
        let symbols = Place.Kind.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "two kinds share a glyph")
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }

    /// D-018: nothing outside Theme picks a raw colour. There are more
    /// kinds than meanings, so kinds may share a colour — but never
    /// invent one.
    func testEveryPlaceKindDrawsFromTheAppsPalette() {
        let vocabulary: Set<Color> = [
            Theme.route, Theme.google, Theme.win, Theme.pro, Theme.armed, Theme.recording,
        ]
        for kind in Place.Kind.allCases {
            XCTAssertTrue(vocabulary.contains(kind.color), "\(kind.rawValue) uses a colour outside Theme")
        }
    }

    /// The three the app has always had keep their own colours, so a
    /// glance at Home still separates home from work from school.
    func testTheDailyThreeStayVisuallyDistinct() {
        let daily: [Place.Kind] = [.home, .work, .school]
        XCTAssertEqual(Set(daily.map(\.color)).count, daily.count)
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
