import Foundation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData

/// The kit/app boundary for recording: feeds converted samples through
/// TripRecorder; at trip start it predicts the destination and snapshots
/// the provider's plan (FR-5/FR-6); on a finalized trip it runs
/// StopDetector + RouteMatcher, attaches the matching snapshot, and
/// persists everything. Every rule lives in the kit; this object only
/// wires and stores — which is exactly what the app-target tests exercise.
@MainActor
@Observable
final class RecordingPipeline {
    private(set) var recorderState: TripRecorder.State = .idle
    private(set) var lastOutcome: String?
    /// The in-flight departure snapshot fetch; exposed so tests (and the
    /// UI, if it cares) can await it.
    private(set) var snapshotFetch: Task<Void, Never>?

    private var recorder: TripRecorder
    private let context: ModelContext
    private let timezoneID: String
    private let routesProvider: (any RoutesProviding)?
    private var pendingSnapshots: [PlanSnapshot] = []

    init(
        context: ModelContext,
        timezoneID: String = TimeZone.current.identifier,
        routesProvider: (any RoutesProviding)? = nil
    ) {
        self.context = context
        self.timezoneID = timezoneID
        self.routesProvider = routesProvider
        self.recorder = TripRecorder(timezoneID: timezoneID)
    }

    var isRecording: Bool { recorderState == .recording }
    var liveTrack: [TrackPoint] { recorder.liveTrack }
    var recordingStartedAt: Date? { recorder.recordingStartedAt }

    func ingest(location point: TrackPoint) {
        handle(recorder.ingest(location: point))
    }

    func ingest(motion sample: TripRecorder.MotionSample) {
        handle(recorder.ingest(motion: sample))
    }

    func startManualRecording() {
        recorder.startManualRecording(at: .now)
        recorderState = recorder.state
        lastOutcome = "Recording (manual)"
    }

    func stopManualRecording() {
        handle(recorder.stopRecording())
    }

    private func handle(_ output: TripRecorder.Output?) {
        recorderState = recorder.state
        guard let output else { return }
        switch output {
        case .tripStarted(let departure):
            lastOutcome = "Recording"
            beginSnapshotFetch(departure: departure)
        case .tripDiscarded(let reason):
            lastOutcome = reason == .tooShort ? "Trip too short to keep" : "Trip too brief to keep"
            clearPendingSnapshots()
        case .tripFinalized(let trip):
            persist(trip)
        }
    }

    // MARK: Departure snapshot (FR-5/FR-6)

    private func beginSnapshotFetch(departure: Date) {
        guard let routesProvider, let originPoint = recorder.liveTrack.first else { return }
        snapshotFetch = Task { [weak self] in
            await self?.fetchSnapshots(
                provider: routesProvider,
                originPoint: originPoint,
                departure: departure
            )
        }
    }

    private func fetchSnapshots(
        provider: any RoutesProviding,
        originPoint: TrackPoint,
        departure: Date
    ) async {
        do {
            let places = try context.fetch(FetchDescriptor<PlaceRecord>()).map { $0.place() }
            let origin = RouteMatcher.place(containing: originPoint.coordinate, in: places)
            let history = try context.fetch(FetchDescriptor<TripRecord>())
                .compactMap { try? $0.trip() }
            let predictor = DestinationPredictor(trips: history)
            let advice = predictor.advice(
                fromOrigin: origin?.id, at: departure, timezoneID: timezoneID
            )
            let targets: [UUID] = switch advice {
            case .snapshotOne(let top): [top.destinationPlaceID]
            case .snapshotTwo(let first, let second):
                [first.destinationPlaceID, second.destinationPlaceID]
            case .none: []
            }
            for targetID in targets {
                guard let place = places.first(where: { $0.id == targetID }) else { continue }
                if let snapshot = try? await provider.computeSnapshot(
                    from: originPoint.coordinate,
                    to: place.coordinate,
                    destinationPlaceID: place.id
                ) {
                    pendingSnapshots.append(snapshot)
                }
            }
        } catch {
            // No comparison for this trip — recording is never blocked
            // by the provider (FR-3).
        }
    }

    private func clearPendingSnapshots() {
        pendingSnapshots.removeAll()
        snapshotFetch = nil
    }

    // MARK: Persistence

    private func persist(_ trip: Trip) {
        defer { clearPendingSnapshots() }
        do {
            var enriched = trip
            enriched.stopEvents = StopDetector.stopEvents(in: trip.points)

            let places = try context.fetch(FetchDescriptor<PlaceRecord>()).map { $0.place() }
            let variantRecords = try context.fetch(FetchDescriptor<VariantRecord>())
            let variants = variantRecords.compactMap { try? $0.variant() }

            // The snapshot whose predicted destination matches where the
            // drive actually ended; mispredictions are simply dropped.
            let destination = trip.points.last.flatMap {
                RouteMatcher.place(containing: $0.coordinate, in: places)
            }
            let snapshot = destination.flatMap { arrived in
                pendingSnapshots.first { $0.destinationPlaceID == arrived.id }
            }
            enriched.snapshotID = snapshot?.id

            let result = RouteMatcher.assign(
                trip: enriched, places: places, variants: variants, snapshot: snapshot
            )
            if let newVariant = result.newVariant {
                context.insert(VariantRecord(newVariant))
            } else if let variantID = result.variantID,
                      let record = variantRecords.first(where: { $0.id == variantID }) {
                record.tripCount += 1
            }
            if let snapshot {
                context.insert(try SnapshotRecord(snapshot))
            }
            context.insert(try TripRecord(result.trip))
            try context.save()
            lastOutcome = "Trip saved"
        } catch {
            // Never lose a drive silently: surface the failure.
            lastOutcome = "Could not save trip: \(error.localizedDescription)"
        }
    }
}
