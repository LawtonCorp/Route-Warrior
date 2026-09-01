import Foundation
import Testing
@testable import RouteWarriorKit

/// References drive a straight 3 km equator route at constant speeds, so
/// the elapsed-at-distance curve is hand arithmetic: at 15 m/s, 1500 m
/// takes 100 s.
struct GhostRaceTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let metersPerDegree = 111_195.08

    private var route: Polyline {
        Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 3_000 / metersPerDegree),
        ])
    }

    private func coordinate(atMeters m: Double) -> Coordinate {
        Coordinate(latitude: 0, longitude: m / metersPerDegree)
    }

    /// A constant-speed run: a point every 10 s until 3 km is covered.
    private func referenceTrip(speedMps: Double) -> Trip {
        var points: [TrackPoint] = []
        var covered = 0.0
        var time = t0
        while covered <= 3_000 {
            points.append(TrackPoint(
                coordinate: coordinate(atMeters: covered),
                timestamp: time,
                speedMps: speedMps,
                horizontalAccuracyM: 5
            ))
            covered += speedMps * 10
            time = time.addingTimeInterval(10)
        }
        return Trip(startedAt: t0, endedAt: time, timezoneID: "America/Chicago", points: points)
    }

    @Test func profileInterpolatesElapsedAtDistance() {
        let profile = GhostRace.ReferenceProfile(trip: referenceTrip(speedMps: 15), along: route)
        #expect(profile != nil)
        let elapsed = profile?.elapsed(atAlongMeters: 1_500)
        #expect(elapsed != nil && abs(elapsed! - 100) < 1)
        // Clamps at the ends.
        #expect(profile?.elapsed(atAlongMeters: -50) == 0)
        let atEnd = profile?.elapsed(atAlongMeters: 10_000)
        #expect(atEnd != nil && atEnd! >= 190)
    }

    @Test func statusReportsAheadAndBehind() {
        let profile = GhostRace.ReferenceProfile(trip: referenceTrip(speedMps: 15), along: route)!
        let ahead = GhostRace.status(
            myElapsed: 90, position: coordinate(atMeters: 1_500), along: route, reference: profile
        )
        #expect(ahead != nil)
        #expect(abs(ahead!.aheadSeconds - 10) < 1)
        #expect(abs(ahead!.distanceAlongM - 1_500) < 5)
        #expect(abs(ahead!.routeLengthM - 3_000) < 5)

        let behind = GhostRace.status(
            myElapsed: 110, position: coordinate(atMeters: 1_500), along: route, reference: profile
        )
        #expect(abs(behind!.aheadSeconds + 10) < 1)
    }

    @Test func averagedProfileMeansTheReferences() {
        // 15 m/s reaches 1500 m in 100 s; 30 m/s in 50 s; the average pace
        // curve reads 75 s there.
        let profile = GhostRace.ReferenceProfile(
            averaging: [referenceTrip(speedMps: 15), referenceTrip(speedMps: 30)],
            along: route
        )
        #expect(profile != nil)
        let elapsed = profile?.elapsed(atAlongMeters: 1_500)
        #expect(elapsed != nil && abs(elapsed! - 75) < 2)
    }

    @Test func backwardGPSscatterIsDroppedFromTheCurve() {
        var points = [0.0, 150, 140, 300].enumerated().map { i, m in
            TrackPoint(
                coordinate: coordinate(atMeters: m),
                timestamp: t0.addingTimeInterval(Double(i) * 10),
                speedMps: 15,
                horizontalAccuracyM: 5
            )
        }
        points.append(TrackPoint(
            coordinate: coordinate(atMeters: 450),
            timestamp: t0.addingTimeInterval(40),
            speedMps: 15,
            horizontalAccuracyM: 5
        ))
        let trip = Trip(startedAt: t0, endedAt: t0.addingTimeInterval(40), timezoneID: "America/Chicago", points: points)
        let profile = GhostRace.ReferenceProfile(trip: trip, along: route)
        #expect(profile != nil)
        // The 140 m regression is skipped; the curve stays monotonic.
        let alongs = profile!.samples.map(\.alongMeters)
        #expect(alongs == alongs.sorted())
        #expect(profile!.samples.count == 4)
    }

    @Test func degenerateInputsYieldNil() {
        let lonely = Trip(
            startedAt: t0, endedAt: t0, timezoneID: "America/Chicago",
            points: [TrackPoint(coordinate: coordinate(atMeters: 0), timestamp: t0, speedMps: 0, horizontalAccuracyM: 5)]
        )
        #expect(GhostRace.ReferenceProfile(trip: lonely, along: route) == nil)
        #expect(GhostRace.ReferenceProfile(averaging: [], along: route) == nil)
    }
}
