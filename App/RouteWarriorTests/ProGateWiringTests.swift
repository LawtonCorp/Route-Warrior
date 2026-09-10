import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-050 wiring: the free tier never asks Google. The pipeline holds both
/// providers; which ones it calls is the tier's decision, read at every
/// request, so a purchase mid-session changes the next departure.
@MainActor
final class ProGateWiringTests: XCTestCase {
    /// A provider that answers with a plan stamped with its own name and
    /// counts how often it was asked. Main-actor so the counter is
    /// Sendable, as `RoutesProviding` requires.
    @MainActor
    private final class CountingStub: RoutesProviding {
        let provider: PlanSnapshot.Provider
        private(set) var calls = 0

        init(_ provider: PlanSnapshot.Provider) {
            self.provider = provider
        }

        func computeSnapshot(
            from origin: Coordinate,
            to destination: Coordinate,
            destinationPlaceID: UUID?
        ) async throws -> PlanSnapshot {
            calls += 1
            return PlanSnapshot(
                provider: provider,
                requestedAt: .now,
                destinationPlaceID: destinationPlaceID,
                polyline: Polyline(coordinates: [origin, destination]),
                distanceM: Geo.distanceMeters(from: origin, to: destination),
                staticDuration: 600,
                trafficDuration: 700
            )
        }
    }

    private func pipeline(tier: TierPolicy.Tier) throws -> (RecordingPipeline, apple: CountingStub, google: CountingStub) {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let apple = CountingStub(.appleMaps)
        let google = CountingStub(.googleRoutes)
        let pipeline = RecordingPipeline(
            context: ModelContext(container),
            timezoneID: "America/Chicago",
            providers: [.appleMaps: apple, .googleRoutes: google],
            tier: { tier }
        )
        return (pipeline, apple, google)
    }

    func testFreeAsksAppleOnlyAndProAsksBoth() async throws {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let destination = Coordinate(latitude: 0, longitude: 0.05)

        let (free, freeApple, freeGoogle) = try pipeline(tier: .free)
        XCTAssertEqual(free.availableProviders, [.appleMaps, .googleRoutes])
        XCTAssertEqual(free.snapshotProviders, [.appleMaps])
        let freePlans = await free.computePlans(from: origin, to: destination, destinationPlaceID: nil)
        XCTAssertEqual(freePlans.map(\.provider), [.appleMaps])
        XCTAssertEqual(freeApple.calls, 1)
        XCTAssertEqual(freeGoogle.calls, 0)

        let (pro, proApple, proGoogle) = try pipeline(tier: .pro)
        XCTAssertEqual(pro.snapshotProviders, [.appleMaps, .googleRoutes])
        let proPlans = await pro.computePlans(from: origin, to: destination, destinationPlaceID: nil)
        XCTAssertEqual(proPlans.map(\.provider), [.appleMaps, .googleRoutes])
        XCTAssertEqual(proApple.calls, 1)
        XCTAssertEqual(proGoogle.calls, 1)
    }

    @MainActor
    private final class TierBox {
        var tier: TierPolicy.Tier = .free
    }

    /// The tier is read per request, not captured at launch.
    func testAPurchaseTakesEffectOnTheNextRequest() async throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let google = CountingStub(.googleRoutes)
        let box = TierBox()
        let pipeline = RecordingPipeline(
            context: ModelContext(container),
            providers: [.appleMaps: CountingStub(.appleMaps), .googleRoutes: google],
            tier: { box.tier }
        )
        let origin = Coordinate(latitude: 0, longitude: 0)
        let destination = Coordinate(latitude: 0, longitude: 0.05)
        _ = await pipeline.computePlans(from: origin, to: destination, destinationPlaceID: nil)
        XCTAssertEqual(google.calls, 0)
        box.tier = .pro
        _ = await pipeline.computePlans(from: origin, to: destination, destinationPlaceID: nil)
        XCTAssertEqual(google.calls, 1)
    }
}
