import Foundation
import Testing
@testable import RouteWarriorKit

/// Turns are counted from the shape of the line alone. Every track here is
/// drawn by `TurtleTrack` from legs and arcs of a known radius, so the
/// expected counts follow from the geometry, not from the counter.
struct TurnCounterTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Corners

    @Test func aStraightRoadHasNoTurns() {
        var track = TurtleTrack()
        track.straight(500)
        #expect(TurnCounter.turns(along: track.polyline).isEmpty)
        #expect(TurnCounter.count(along: track.polyline) == .zero)
    }

    @Test func aRightAngleCornerIsOneTurnAtTheCorner() {
        var track = TurtleTrack(heading: 0)
        track.straight(100)
        track.curve(radius: 10, degrees: 90)
        let apex = track.current
        track.straight(100)

        let turns = TurnCounter.turns(along: track.polyline)
        #expect(turns.count == 1)
        guard let turn = turns.first else { return }
        #expect(turn.direction == .right)
        #expect(turn.degrees > 60 && turn.degrees <= 90)
        // The sharpest point sits on the corner, not somewhere along the legs.
        #expect(Geo.distanceMeters(from: turn.coordinate, to: apex) < 15)
        #expect(abs(turn.alongMeters - 108) < 15)
    }

    @Test func clockwiseIsRightAndAnticlockwiseIsLeft() {
        var right = TurtleTrack(heading: 90)
        right.straight(100)
        right.curve(radius: 12, degrees: 90)
        right.straight(100)
        #expect(TurnCounter.count(along: right.polyline) == TurnCount(right: 1))

        var left = TurtleTrack(heading: 90)
        left.straight(100)
        left.curve(radius: 12, degrees: -90)
        left.straight(100)
        #expect(TurnCounter.count(along: left.polyline) == TurnCount(left: 1))
    }

    /// Heading east then north is a left turn — a fact about compasses,
    /// not about this code.
    @Test func headingChangeSignMatchesTheCompass() {
        #expect(TurnCounter.signedChange(from: 90, to: 0) == -90)
        #expect(TurnCounter.signedChange(from: 0, to: 90) == 90)
        #expect(TurnCounter.signedChange(from: 350, to: 10) == 20)
        #expect(TurnCounter.signedChange(from: 10, to: 350) == -20)
        #expect(abs(TurnCounter.signedChange(from: 0, to: 180)) == 180)
    }

    @Test func aLeftThenARightAreCountedInOrder() {
        var track = TurtleTrack()
        track.straight(120)
        track.curve(radius: 10, degrees: -90)
        track.straight(150)
        track.curve(radius: 10, degrees: 90)
        track.straight(120)

        let turns = TurnCounter.turns(along: track.polyline)
        #expect(turns.map(\.direction) == [.left, .right])
        #expect(turns.count == 2 && turns[0].alongMeters < turns[1].alongMeters)
        #expect(TurnCounter.count(along: track.polyline) == TurnCount(left: 1, right: 1))
    }

    /// Around a block: two rights separated by a leg longer than the
    /// window are two turns, not one long one.
    @Test func twoCornersOnOneBlockAreTwoTurns() {
        var track = TurtleTrack()
        track.straight(100)
        track.curve(radius: 8, degrees: 90)
        track.straight(60)
        track.curve(radius: 8, degrees: 90)
        track.straight(100)
        #expect(TurnCounter.count(along: track.polyline) == TurnCount(right: 2))
    }

    // MARK: Bends versus turns

    @Test func aSweepingHighwayCurveIsNotATurn() {
        for radius in [100.0, 150.0, 400.0] {
            var track = TurtleTrack()
            track.straight(100)
            track.curve(radius: radius, degrees: 90)
            track.straight(100)
            #expect(TurnCounter.count(along: track.polyline) == .zero, "radius \(radius)")
        }
    }

    @Test func aTightCornerIsATurnWhateverItsCurbRadius() {
        for radius in [5.0, 15.0, 20.0] {
            var track = TurtleTrack()
            track.straight(100)
            track.curve(radius: radius, degrees: -90)
            track.straight(100)
            #expect(TurnCounter.count(along: track.polyline) == TurnCount(left: 1), "radius \(radius)")
        }
    }

    @Test func aReversalIsAUTurnNotALeftAndARight() {
        var track = TurtleTrack()
        track.straight(100)
        track.curve(radius: 5, degrees: -180)
        track.straight(100)
        let count = TurnCounter.count(along: track.polyline)
        #expect(count == TurnCount(uTurn: 1))
        #expect(count.total == 1)
    }

    // MARK: Degenerate lines

    @Test func aLineTooShortToTurnCountsNothing() {
        var track = TurtleTrack()
        track.straight(30)
        #expect(TurnCounter.turns(along: track.polyline).isEmpty)
        #expect(TurnCounter.turns(along: Polyline(coordinates: [])).isEmpty)
        #expect(TurnCounter.turns(along: Polyline(coordinates: [Coordinate(latitude: 0, longitude: 0)])).isEmpty)
    }

    @Test func aZeroStepCannotLoopForever() {
        var track = TurtleTrack()
        track.straight(200)
        var config = TurnCounter.Config()
        config.stepMeters = 0
        #expect(TurnCounter.turns(along: track.polyline, config: config).isEmpty)
    }

    @Test func repeatedFixesInOnePlaceCollapse() {
        let spot = Coordinate(latitude: 0, longitude: 0)
        let line = Polyline(coordinates: Array(repeating: spot, count: 50) + [Coordinate(latitude: 0.001, longitude: 0)])
        #expect(TurnCounter.spaced(line, config: TurnCounter.Config()).coordinates.count == 2)
    }

    // MARK: Trips

    /// Sixty seconds at a red light, with the fix wandering up to eight
    /// metres in every direction, must not read as turning.
    @Test func aHaltedPhoneWanderingAtARedLightDoesNotTurn() {
        var before = TurtleTrack(heading: 90, spacing: 15)
        before.straight(300)
        var after = TurtleTrack(heading: 90, spacing: 15)
        after.straight(300)

        var points = before.trackPoints(from: t0, speedMps: 15)
        let corner = before.current
        var seed: UInt64 = 42
        func noise() -> Double {
            // A small deterministic generator: reproducible, and wide enough
            // to scribble over the halt.
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Double(seed >> 11) / Double(1 << 53)) * 16 - 8
        }
        for second in 0..<60 {
            points.append(TrackPoint(
                coordinate: Coordinate(
                    latitude: corner.latitude + noise() / TurtleTrack.metersPerDegree,
                    longitude: corner.longitude + noise() / TurtleTrack.metersPerDegree
                ),
                timestamp: t0.addingTimeInterval(20 + Double(second)),
                speedMps: 0,
                horizontalAccuracyM: 8
            ))
        }
        let resume = t0.addingTimeInterval(80)
        points += after.trackPoints(from: resume, speedMps: 15).map { point in
            var moved = point
            moved.coordinate.longitude += corner.longitude
            return moved
        }
        let trip = Trip(startedAt: t0, endedAt: resume.addingTimeInterval(20), timezoneID: "UTC", points: points)

        #expect(TurnCounter.count(for: trip) == .zero)
        // The halt's samples are what got dropped: the moving ones survive.
        #expect(TurnCounter.track(of: trip).coordinates.count == before.points.count + after.points.count)
    }

    @Test func aPoorFixIsDroppedAndAnUnknownSpeedIsKept() {
        let good = TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0), timestamp: t0, speedMps: 10, horizontalAccuracyM: 5)
        let vague = TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.001), timestamp: t0, speedMps: 10, horizontalAccuracyM: 200)
        let unknown = TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.002), timestamp: t0, speedMps: -1, horizontalAccuracyM: -1)
        let halted = TrackPoint(coordinate: Coordinate(latitude: 0, longitude: 0.003), timestamp: t0, speedMps: 0.2, horizontalAccuracyM: 5)
        let trip = Trip(startedAt: t0, endedAt: t0, timezoneID: "UTC", points: [good, vague, unknown, halted])
        #expect(TurnCounter.track(of: trip).coordinates == [good.coordinate, unknown.coordinate])
    }

    @Test func aTripWithACornerCountsItsTurn() {
        var track = TurtleTrack(spacing: 10)
        track.straight(200)
        track.curve(radius: 10, degrees: -90)
        track.straight(200)
        let trip = Trip(startedAt: t0, endedAt: t0.addingTimeInterval(60), timezoneID: "UTC", points: track.trackPoints(from: t0, speedMps: 12))
        #expect(TurnCounter.count(for: trip) == TurnCount(left: 1))
    }

    // MARK: Typical

    @Test func theTypicalCountIsTheMedianPerDirection() {
        let counts = [
            TurnCount(left: 1, right: 2, uTurn: 0),
            TurnCount(left: 1, right: 3, uTurn: 0),
            TurnCount(left: 5, right: 3, uTurn: 1),
        ]
        #expect(TurnCount.median(of: counts) == TurnCount(left: 1, right: 3, uTurn: 0))
        // An even number of drives takes the lower middle: a whole turn a
        // drive actually had.
        #expect(TurnCount.median(of: [TurnCount(left: 2), TurnCount(left: 4)]) == TurnCount(left: 2))
        #expect(TurnCount.median(of: []) == nil)
    }

    @Test func typicalIgnoresTripsWithNoShape() {
        var track = TurtleTrack(spacing: 10)
        track.straight(150)
        track.curve(radius: 10, degrees: 90)
        track.straight(150)
        let real = Trip(startedAt: t0, endedAt: t0, timezoneID: "UTC", points: track.trackPoints(from: t0, speedMps: 12))
        let empty = Trip(startedAt: t0, endedAt: t0, timezoneID: "UTC", points: [])
        let dot = Trip(startedAt: t0, endedAt: t0, timezoneID: "UTC", points: Array(real.points.prefix(1)))

        #expect(TurnCounter.typical(for: [empty, dot]) == nil)
        #expect(TurnCounter.typical(for: [empty, real, dot]) == TurnCount(right: 1))
    }

    // MARK: Model

    @Test func countsAndTurnsRoundTripThroughJSON() throws {
        let turn = Turn(coordinate: Coordinate(latitude: 1, longitude: 2), alongMeters: 30, degrees: -88, direction: .left)
        let count = TurnCount(turns: [turn, Turn(coordinate: turn.coordinate, alongMeters: 60, degrees: 91, direction: .right), Turn(coordinate: turn.coordinate, alongMeters: 90, degrees: 170, direction: .uTurn)])
        #expect(count == TurnCount(left: 1, right: 1, uTurn: 1))
        #expect(count.total == 3)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode(TurnCount.self, from: encoder.encode(count)) == count)
        #expect(try decoder.decode(Turn.self, from: encoder.encode(turn)) == turn)
    }

    @Test func directionFollowsTheSignAndTheReversalThreshold() {
        let config = TurnCounter.Config()
        #expect(TurnCounter.direction(of: -90, config: config) == .left)
        #expect(TurnCounter.direction(of: 90, config: config) == .right)
        #expect(TurnCounter.direction(of: 135, config: config) == .uTurn)
        #expect(TurnCounter.direction(of: -170, config: config) == .uTurn)
    }
}
