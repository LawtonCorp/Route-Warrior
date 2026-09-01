import Foundation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData

/// The kit/app boundary for recording: feeds converted samples through
/// TripRecorder, and on a finalized trip runs StopDetector + RouteMatcher
/// and persists the results. Every rule lives in the kit; this object only
/// wires and stores — which is exactly what the app-target tests exercise.
@MainActor
@Observable
final class RecordingPipeline {
    private(set) var recorderState: TripRecorder.State = .idle
    private(set) var lastOutcome: String?

    private var recorder: TripRecorder
    private let context: ModelContext

    init(context: ModelContext, timezoneID: String = TimeZone.current.identifier) {
        self.context = context
        self.recorder = TripRecorder(timezoneID: timezoneID)
    }

    var isRecording: Bool { recorderState == .recording }

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
        case .tripStarted:
            lastOutcome = "Recording"
        case .tripDiscarded(let reason):
            lastOutcome = reason == .tooShort ? "Trip too short to keep" : "Trip too brief to keep"
        case .tripFinalized(let trip):
            persist(trip)
        }
    }

    private func persist(_ trip: Trip) {
        do {
            var enriched = trip
            enriched.stopEvents = StopDetector.stopEvents(in: trip.points)

            let places = try context.fetch(FetchDescriptor<PlaceRecord>()).map { $0.place() }
            let variantRecords = try context.fetch(FetchDescriptor<VariantRecord>())
            let variants = variantRecords.compactMap { try? $0.variant() }

            let result = RouteMatcher.assign(trip: enriched, places: places, variants: variants)
            if let newVariant = result.newVariant {
                context.insert(VariantRecord(newVariant))
            } else if let variantID = result.variantID,
                      let record = variantRecords.first(where: { $0.id == variantID }) {
                record.tripCount += 1
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
