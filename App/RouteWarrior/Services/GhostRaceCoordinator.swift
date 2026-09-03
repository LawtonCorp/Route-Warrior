import Foundation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData

/// Presentation seam so the race logic is testable without ActivityKit —
/// the real presenter drives the Live Activity; tests use a spy.
@MainActor
protocol GhostRacePresenting: AnyObject {
    func startRace(destinationName: String, routeName: String, referenceLabel: String)
    func updateRace(aheadSeconds: Double, progress: Double, referenceLabel: String)
    func endRace()
}

/// Drives the ghost race during a recording (FR-15): recognizes the variant
/// once the drive commits to a known shape (kit `liveMatch`), builds the
/// reference profile (personal best, or bucket average per setting), and
/// pushes ahead/behind updates at a throttled cadence.
@MainActor
@Observable
final class GhostRaceCoordinator {
    enum Reference: String {
        case personalBest
        case bucketAverage
    }

    private(set) var status: GhostRace.Status?
    var reference: Reference = .personalBest

    private let context: ModelContext
    // Strong: the presenter never references the coordinator back, and the
    // app hands one in inline — a weak slot would drop it immediately.
    private let presenter: (any GhostRacePresenting)?
    private let policy = TierPolicy()
    private var tierProvider: () -> TierPolicy.Tier

    private var matchedVariantID: UUID?
    private var profile: GhostRace.ReferenceProfile?
    private var routeLine: Polyline?
    private var lastPushAt: Date = .distantPast
    private static let pushInterval: TimeInterval = 15

    init(
        context: ModelContext,
        presenter: (any GhostRacePresenting)?,
        tierProvider: @escaping () -> TierPolicy.Tier = { .pro }
    ) {
        self.context = context
        self.presenter = presenter
        self.tierProvider = tierProvider
    }

    func tripBegan() {
        reset()
    }

    func tripEnded() {
        if matchedVariantID != nil {
            presenter?.endRace()
        }
        reset()
    }

    /// Fed by LocationService with the live track after every sample.
    func ingest(track: [TrackPoint], startedAt: Date) {
        guard policy.ghostRaceAvailable(for: tierProvider()) else { return }
        guard let last = track.last else { return }
        guard last.timestamp.timeIntervalSince(lastPushAt) >= Self.pushInterval else { return }
        lastPushAt = last.timestamp

        let partial = Polyline(coordinates: track.map(\.coordinate))
        if matchedVariantID == nil {
            attemptMatch(partial: partial, track: track)
        }
        guard let profile, let routeLine else { return }
        guard let raceStatus = GhostRace.status(
            myElapsed: last.timestamp.timeIntervalSince(startedAt),
            position: last.coordinate,
            along: routeLine,
            reference: profile
        ) else { return }
        status = raceStatus
        presenter?.updateRace(
            aheadSeconds: raceStatus.aheadSeconds,
            progress: raceStatus.routeLengthM > 0
                ? min(1, max(0, raceStatus.distanceAlongM / raceStatus.routeLengthM))
                : 0,
            referenceLabel: referenceLabel
        )
    }

    private var referenceLabel: String {
        reference == .personalBest ? "personal best" : "your average"
    }

    private func attemptMatch(partial: Polyline, track: [TrackPoint]) {
        guard let originPoint = track.first else { return }
        do {
            let places = try context.fetch(FetchDescriptor<PlaceRecord>()).map { $0.place() }
            guard let origin = RouteMatcher.place(containing: originPoint.coordinate, in: places) else { return }
            let candidates = try context.fetch(FetchDescriptor<VariantRecord>())
                .filter { $0.originPlaceID == origin.id }
                .compactMap { try? $0.variant() }
            guard let match = RouteMatcher.liveMatch(partialTrack: partial, candidates: candidates),
                  let variant = candidates.first(where: { $0.id == match.variantID })
            else { return }

            let history = try context.fetch(FetchDescriptor<TripRecord>())
                .filter { $0.variantID == variant.id && !$0.excludedFromStats }
                .compactMap { try? $0.trip() }
            guard !history.isEmpty else { return }

            let referenceProfile: GhostRace.ReferenceProfile?
            switch reference {
            case .personalBest:
                referenceProfile = history
                    .min { $0.duration < $1.duration }
                    .flatMap { GhostRace.ReferenceProfile(trip: $0, along: variant.representativePolyline) }
            case .bucketAverage:
                referenceProfile = GhostRace.ReferenceProfile(
                    averaging: history, along: variant.representativePolyline
                )
            }
            guard let referenceProfile else { return }

            matchedVariantID = variant.id
            profile = referenceProfile
            routeLine = variant.representativePolyline
            let destinationName = places.first { $0.id == variant.destinationPlaceID }?.name ?? "destination"
            presenter?.startRace(
                destinationName: destinationName,
                routeName: variant.displayName,
                referenceLabel: referenceLabel
            )
        } catch {
            // No race, no harm — recording is untouched.
        }
    }

    private func reset() {
        matchedVariantID = nil
        profile = nil
        routeLine = nil
        status = nil
        lastPushAt = .distantPast
    }
}
