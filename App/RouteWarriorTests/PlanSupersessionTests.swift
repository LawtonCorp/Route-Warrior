import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-055: one destination per drive. A guess still being fetched when
/// the driver names the destination is dropped when it lands; the
/// one-tap pick replaces guesses instead of joining them; a plan that
/// lands after the drive ended belongs to no drive.
@MainActor
final class PlanSupersessionTests: XCTestCase {
    private let metersPerDegree = 111_195.08
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// Answers only when opened, so a fetch can be caught in flight.
    @MainActor
    private final class GatedRoutes: RoutesProviding {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var calls = 0

        func open() {
            opened = true
            let resumed = waiters
            waiters.removeAll()
            for waiter in resumed { waiter.resume() }
        }

        func computeSnapshot(
            from origin: Coordinate,
            to destination: Coordinate,
            destinationPlaceID: UUID?
        ) async throws -> PlanSnapshot {
            calls += 1
            if !opened {
                await withCheckedContinuation { waiters.append($0) }
            }
            return PlanSnapshot(
                requestedAt: .now,
                destinationPlaceID: destinationPlaceID,
                polyline: Polyline(coordinates: [origin, destination]),
                distanceM: Geo.distanceMeters(from: origin, to: destination),
                staticDuration: 600,
                trafficDuration: 700
            )
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

    /// Home, School and Gym, with three school runs from home in the
    /// same weekday slot so the predictor guesses School.
    private func seed(_ context: ModelContext) throws -> (home: Place, school: Place, gym: Place) {
        let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
        let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.09))
        let gym = Place(name: "Gym", coordinate: Coordinate(latitude: 0.05, longitude: 0.02))
        for place in [home, school, gym] { context.insert(PlaceRecord(place)) }
        for week in 0..<3 {
            let start = t0.addingTimeInterval(Double(week) * 7 * 86_400)
            context.insert(try TripRecord(Trip(
                startedAt: start,
                endedAt: start.addingTimeInterval(700),
                timezoneID: "America/Chicago",
                points: [point(east: 0, at: start, speed: 12), point(east: 600, at: start.addingTimeInterval(50), speed: 12)],
                originPlaceID: home.id,
                destinationPlaceID: school.id
            )))
        }
        try context.save()
        return (home, school, gym)
    }

    /// Starts an auto-detected drive from Home at the predictor's slot
    /// and returns the time of the last sample.
    private func startDrive(_ pipeline: RecordingPipeline) -> Date {
        let departure = t0.addingTimeInterval(3 * 7 * 86_400)
        pipeline.ingest(motion: .init(kind: .automotive, confidence: .high, timestamp: departure))
        var time = departure
        for east in stride(from: 0.0, through: 600, by: 15) {
            pipeline.ingest(location: point(east: east, at: time, speed: 15))
            time = time.addingTimeInterval(1)
        }
        return time
    }

    func testATypedDestinationSupersedesAGuessStillInFlight() async throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let places = try seed(context)
        let routes = GatedRoutes()
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago", routesProvider: routes)

        _ = startDrive(pipeline)
        XCTAssertTrue(pipeline.isRecording)
        let guess = try XCTUnwrap(pipeline.snapshotFetch, "the departure prediction is in flight")
        XCTAssertTrue(pipeline.plansForCurrentDrive.isEmpty)

        // The driver types Gym and taps Go while School's plan is still loading.
        let typed = PlanSnapshot(
            provider: .appleMaps, requestedAt: .now, destinationPlaceID: places.gym.id,
            polyline: Polyline(coordinates: [places.home.coordinate, places.gym.coordinate]),
            distanceM: 6_000, staticDuration: 500, trafficDuration: 500
        )
        pipeline.startPlannedDrive(with: [typed])
        routes.open()
        await guess.value

        XCTAssertEqual(pipeline.plansForCurrentDrive.map(\.id), [typed.id], "the guess landed late and was dropped")
        XCTAssertEqual(Set(pipeline.plansForCurrentDrive.map(\.destinationPlaceID)), [places.gym.id])
        XCTAssertTrue(pipeline.log.contains { $0.text.contains("dropped") })
    }

    func testTheOneTapPickReplacesTheGuessAndKeepsAConfirmedOne() async throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let places = try seed(context)
        let routes = GatedRoutes()
        routes.open()
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago", routesProvider: routes)

        _ = startDrive(pipeline)
        await pipeline.snapshotFetch?.value
        XCTAssertEqual(pipeline.plansForCurrentDrive.map(\.destinationPlaceID), [places.school.id], "the guess landed")
        let callsAfterGuess = routes.calls

        // "Where are you headed?" → Gym: the guess goes, Gym's plan comes.
        pipeline.requestSnapshot(to: places.gym.id)
        await pipeline.snapshotFetch?.value
        XCTAssertEqual(pipeline.plansForCurrentDrive.map(\.destinationPlaceID), [places.gym.id])
        XCTAssertEqual(routes.calls, callsAfterGuess + 1)

        // Confirming the same place again keeps the plan already held.
        pipeline.requestSnapshot(to: places.gym.id)
        await pipeline.snapshotFetch?.value
        XCTAssertEqual(pipeline.plansForCurrentDrive.count, 1)
        XCTAssertEqual(routes.calls, callsAfterGuess + 1, "no second fetch from a later point")
    }

    func testAPlanLandingAfterTheDriveEndedBelongsToNoDrive() async throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        _ = try seed(context)
        let routes = GatedRoutes()
        let pipeline = RecordingPipeline(context: context, timezoneID: "America/Chicago", routesProvider: routes)

        _ = startDrive(pipeline)
        let guess = try XCTUnwrap(pipeline.snapshotFetch)
        pipeline.stopManualRecording()
        XCTAssertFalse(pipeline.isRecording)
        routes.open()
        await guess.value
        XCTAssertTrue(pipeline.plansForCurrentDrive.isEmpty, "nothing waits to attach itself to the next drive")
    }
}
