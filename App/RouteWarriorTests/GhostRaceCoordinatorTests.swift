import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// FR-15 wiring, without ActivityKit: a spy presenter proves the
/// coordinator recognizes the variant from the live track, builds the
/// personal-best reference, and reports ahead/behind at hand-computable
/// values (driving 20 m/s against a 15 m/s best ⇒ ahead by d/60 seconds).
@MainActor
final class GhostRaceCoordinatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let metersPerDegree = 111_195.08

    private final class SpyPresenter: GhostRacePresenting {
        var starts: [(destination: String, route: String)] = []
        var updates: [Double] = []
        var ends = 0

        func startRace(destinationName: String, routeName: String, referenceLabel: String) {
            starts.append((destinationName, routeName))
        }

        func updateRace(aheadSeconds: Double, progress: Double, referenceLabel: String) {
            updates.append(aheadSeconds)
        }

        func endRace() {
            ends += 1
        }
    }

    private func point(east: Double, at time: Date, speed: Double) -> TrackPoint {
        TrackPoint(
            coordinate: Coordinate(latitude: 0, longitude: east / metersPerDegree),
            timestamp: time,
            speedMps: speed,
            courseDegrees: 90,
            horizontalAccuracyM: 5
        )
    }

    /// Seeds home→school, a straight 10 km variant, and a 15 m/s best run.
    private func seed(_ context: ModelContext) throws -> (home: Place, school: Place, variant: RouteVariant) {
        let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
        let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
        context.insert(PlaceRecord(home))
        context.insert(PlaceRecord(school))

        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.09),
        ]).resampled(to: 64)
        let variant = RouteVariant(
            originPlaceID: home.id,
            destinationPlaceID: school.id,
            representativePolyline: line,
            autoName: "Route A",
            tripCount: 1
        )
        context.insert(VariantRecord(variant))

        var points: [TrackPoint] = []
        var covered = 0.0
        var time = t0.addingTimeInterval(-86_400)
        while covered <= 0.09 * metersPerDegree {
            points.append(point(east: covered, at: time, speed: 15))
            covered += 150
            time = time.addingTimeInterval(10)
        }
        var best = Trip(
            startedAt: points.first!.timestamp,
            endedAt: points.last!.timestamp,
            timezoneID: "America/Chicago",
            points: points
        )
        best.variantID = variant.id
        best.destinationPlaceID = school.id
        best.originPlaceID = home.id
        context.insert(try TripRecord(best))
        try context.save()
        return (home, school, variant)
    }

    func testRecognizesVariantAndReportsAhead() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        _ = try seed(context)

        let spy = SpyPresenter()
        let coordinator = GhostRaceCoordinator(context: context, presenter: spy)
        coordinator.tripBegan()

        // Drive the same route at 20 m/s — faster than the 15 m/s best.
        var track: [TrackPoint] = []
        for second in 0...120 {
            track.append(point(east: Double(second) * 20, at: t0.addingTimeInterval(Double(second)), speed: 20))
            coordinator.ingest(track: track, startedAt: t0)
        }

        XCTAssertEqual(spy.starts.count, 1)
        XCTAssertEqual(spy.starts.first?.destination, "School")
        XCTAssertFalse(spy.updates.isEmpty)
        // At 2400 m in: ahead by 2400/15 − 2400/20 = 40 s (±tolerance for
        // sampling and projection).
        if let last = spy.updates.last {
            XCTAssertGreaterThan(last, 30)
            XCTAssertLessThan(last, 50)
        }

        coordinator.tripEnded()
        XCTAssertEqual(spy.ends, 1)
    }

    func testFreeTierNeverRaces() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        _ = try seed(context)

        let spy = SpyPresenter()
        let coordinator = GhostRaceCoordinator(
            context: context, presenter: spy, tierProvider: { .free }
        )
        coordinator.tripBegan()
        var track: [TrackPoint] = []
        for second in 0...90 {
            track.append(point(east: Double(second) * 20, at: t0.addingTimeInterval(Double(second)), speed: 20))
            coordinator.ingest(track: track, startedAt: t0)
        }
        XCTAssertTrue(spy.starts.isEmpty)
        XCTAssertTrue(spy.updates.isEmpty)
    }

    func testOffRouteDriveNeverMatches() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        _ = try seed(context)

        let spy = SpyPresenter()
        let coordinator = GhostRaceCoordinator(context: context, presenter: spy)
        coordinator.tripBegan()
        var track: [TrackPoint] = []
        for second in 0...90 {
            // Due south, away from the only known variant.
            track.append(TrackPoint(
                coordinate: Coordinate(latitude: -Double(second) * 20 / metersPerDegree, longitude: 0),
                timestamp: t0.addingTimeInterval(Double(second)),
                speedMps: 20,
                horizontalAccuracyM: 5
            ))
            coordinator.ingest(track: track, startedAt: t0)
        }
        XCTAssertTrue(spy.starts.isEmpty)
        coordinator.tripEnded()
        XCTAssertEqual(spy.ends, 0)
    }
}
