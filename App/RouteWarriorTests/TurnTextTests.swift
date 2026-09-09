import Foundation
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// The turn counter's wording on the trip, route and plan screens
/// (D-043). Lefts come first because they are the turns that cost time,
/// and a plan or a drive with no turns says so in words.
final class TurnTextTests: XCTestCase {
    /// A flat-frame track on the equator: `legs` are (heading, metres),
    /// each joined by a tight corner drawn as short chords.
    private func polyline(legs: [(heading: Double, meters: Double)]) -> Polyline {
        let metersPerDegree = 111_195.08
        var x = 0.0, y = 0.0
        var heading = legs.first?.heading ?? 0
        var coords = [Coordinate(latitude: 0, longitude: 0)]
        func step(_ meters: Double) {
            x += meters * sin(heading * .pi / 180)
            y += meters * cos(heading * .pi / 180)
            coords.append(Coordinate(latitude: y / metersPerDegree, longitude: x / metersPerDegree))
        }
        for (index, leg) in legs.enumerated() {
            if index > 0 {
                // A 10 m-radius corner in four chords.
                var delta = leg.heading - heading
                if delta > 180 { delta -= 360 }
                if delta <= -180 { delta += 360 }
                let piece = delta / 4
                let chord = 2 * 10 * sin(abs(piece) * .pi / 360)
                for _ in 0..<4 {
                    heading += piece / 2
                    step(chord)
                    heading += piece / 2
                }
            }
            var remaining = leg.meters
            while remaining > 0 {
                step(min(5, remaining))
                remaining -= 5
            }
        }
        return Polyline(coordinates: coords)
    }

    func testLeftsLeadAndUTurnsAppearOnlyWhenTaken() {
        XCTAssertEqual(TurnText.summary(TurnCount(left: 2, right: 3)), "2 left · 3 right")
        XCTAssertEqual(TurnText.summary(TurnCount(left: 0, right: 1, uTurn: 1)), "0 left · 1 right · 1 U-turn")
        XCTAssertEqual(TurnText.summary(TurnCount(left: 4, right: 0, uTurn: 2)), "4 left · 0 right · 2 U-turns")
        XCTAssertEqual(TurnText.summary(.zero), "No turns")
    }

    func testTheCaptionCountsLeftsWithTheRightPlural() {
        XCTAssertEqual(TurnText.lefts(TurnCount(left: 1, right: 9)), "1 left")
        XCTAssertEqual(TurnText.lefts(TurnCount(left: 3)), "3 lefts")
        XCTAssertEqual(TurnText.lefts(.zero), "0 lefts")
    }

    /// The wiring the Plan tab uses: a plan's line goes into the kit's
    /// counter and comes out as words. East, north, east is one left then
    /// one right.
    func testAPlanLineReadsAsItsTurns() {
        let line = polyline(legs: [(90, 200), (0, 200), (90, 200)])
        XCTAssertEqual(TurnText.summary(TurnCounter.count(along: line)), "1 left · 1 right")

        let straight = polyline(legs: [(45, 600)])
        XCTAssertEqual(TurnText.summary(TurnCounter.count(along: straight)), "No turns")
    }
}
