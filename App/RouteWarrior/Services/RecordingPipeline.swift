import Foundation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData

/// The kit/app boundary for recording: feeds converted samples through
/// TripRecorder; at trip start it predicts the destination and snapshots
/// every provider's plan (FR-5/FR-6, "beat both" D-022); on a finalized
/// trip it runs StopDetector + RouteMatcher, attaches the matching
/// snapshots — the preferred provider's as the primary plan, the other as
/// the alternate — and persists everything. Every rule lives in the kit;
/// this object only wires and stores — which is exactly what the
/// app-target tests exercise.
@MainActor
@Observable
final class RecordingPipeline {
    /// One line of the recorder log (D-019): what the recorder did and
    /// when, in plain words, so a field test can be read off the phone.
    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let time: Date
        let text: String
    }

    static let logCapacity = 40
    private static let logDefaultsKey = "recorderLog"
    /// A drive that ends within this distance of a plan's endpoint gets
    /// that plan even when the endpoint is not a saved place (a planned
    /// drive to a searched address, FR-20).
    static let plannedArrivalRadiusM: Double = 200

    private(set) var recorderState: TripRecorder.State = .idle
    private(set) var lastOutcome: String?
    /// Newest last. Survives relaunches through `logStorage` so a drive
    /// during which iOS killed the app still leaves a trace.
    private(set) var log: [LogEntry] = []
    /// The in-flight departure snapshot fetch; exposed so tests (and the
    /// UI, if it cares) can await it.
    private(set) var snapshotFetch: Task<Void, Never>?

    private var recorder: TripRecorder
    private let context: ModelContext
    private let timezoneID: String
    /// Every routing provider this build can reach, by the provider its
    /// snapshots carry.
    private let providers: [PlanSnapshot.Provider: any RoutesProviding]
    /// Whose plan the driver sees — the primary snapshot on the trip.
    private let preference: @MainActor () -> MapProvider
    private let logStorage: UserDefaults?
    private var pendingSnapshots: [PlanSnapshot] = []
    private var samplesThisSegment = 0

    /// FR-6 fallback: fired when a trip starts but no destination clears
    /// the confidence bar. The app answers with a one-tap picker
    /// (notification); the pick calls `requestSnapshot(to:)`.
    var onDestinationUnknown: (@MainActor ([Place]) -> Void)?

    init(
        context: ModelContext,
        timezoneID: String = TimeZone.current.identifier,
        routesProvider: (any RoutesProviding)? = nil,
        providers: [PlanSnapshot.Provider: any RoutesProviding] = [:],
        preference: @escaping @MainActor () -> MapProvider = { MapProvider.default },
        logStorage: UserDefaults? = nil
    ) {
        self.context = context
        self.timezoneID = timezoneID
        var all = providers
        if let routesProvider {
            // v1 spelling: a single Google provider.
            all[.googleRoutes] = routesProvider
        }
        self.providers = all
        self.preference = preference
        self.logStorage = logStorage
        self.recorder = TripRecorder(timezoneID: timezoneID)
        self.log = Self.loadLog(from: logStorage)
    }

    var isRecording: Bool { recorderState == .recording }
    var liveTrack: [TrackPoint] { recorder.liveTrack }
    var recordingStartedAt: Date? { recorder.recordingStartedAt }
    /// Providers this build can ask, Apple first (the default map).
    var availableProviders: [PlanSnapshot.Provider] {
        [PlanSnapshot.Provider.appleMaps, .googleRoutes].filter { providers[$0] != nil }
    }
    /// The plans held for the current drive (for the drive view).
    var plansForCurrentDrive: [PlanSnapshot] { pendingSnapshots }

    func ingest(location point: TrackPoint) {
        if recorder.state != .idle {
            samplesThisSegment += 1
            if samplesThisSegment == 1 {
                note("First location sample since arming (±\(Int(point.horizontalAccuracyM)) m, \(Int(max(0, point.speedMps))) m/s)")
            }
        }
        handle(recorder.ingest(location: point))
    }

    func ingest(motion sample: TripRecorder.MotionSample) {
        handle(recorder.ingest(motion: sample))
    }

    func startManualRecording() {
        recorder.startManualRecording(at: .now)
        recorderState = recorder.state
        samplesThisSegment = 0
        lastOutcome = "Recording (manual)"
        note("Recording started by the Record button")
    }

    /// FR-20: the driver chose a destination and saw the plans. Recording
    /// starts now (unless a drive is already being recorded) and those
    /// plans become the departure snapshots — no second fetch.
    func startPlannedDrive(with snapshots: [PlanSnapshot]) {
        if recorder.state != .recording {
            recorder.startManualRecording(at: .now)
            recorderState = recorder.state
            samplesThisSegment = 0
        }
        pendingSnapshots = snapshots
        lastOutcome = "Recording (planned)"
        note("Recording started from the plan screen with \(snapshots.count) plan(s)")
    }

    func stopManualRecording() {
        handle(recorder.stopRecording())
    }

    // MARK: Plans on demand (FR-20 preview, FR-22 reroute)

    /// Every available provider's plan from `origin` to `destination`.
    /// A failure never interrupts the driver — a missing plan is only a
    /// missing comparison — but it is written to the recorder log, so
    /// "the route never appeared" is answerable after the fact instead of
    /// vanishing into a `try?`.
    func computePlans(
        from origin: Coordinate,
        to destination: Coordinate,
        destinationPlaceID: UUID?
    ) async -> [PlanSnapshot] {
        var plans: [PlanSnapshot] = []
        for provider in availableProviders {
            guard let client = providers[provider] else { continue }
            do {
                plans.append(try await client.computeSnapshot(
                    from: origin, to: destination, destinationPlaceID: destinationPlaceID
                ))
            } catch {
                note("\(provider.displayName) returned no plan — \(Self.describe(error))")
            }
        }
        return plans
    }

    /// A short, human reason for the recorder log. An HTTP status is the
    /// one that matters most: 403 means the key is refused for this API
    /// (a key restricted to iOS apps cannot call the Routes web service).
    nonisolated static func describe(_ error: Error) -> String {
        guard let routes = error as? RoutesClientError else {
            return (error as NSError).localizedDescription
        }
        switch routes {
        case .noAPIKey: return "no API key"
        case .noRoutes: return "no route between those points"
        case let .badResponse(status): return "HTTP \(status)"
        }
    }

    func computePlan(
        from origin: Coordinate,
        to destination: Coordinate,
        destinationPlaceID: UUID?,
        provider: PlanSnapshot.Provider
    ) async -> PlanSnapshot? {
        guard let client = providers[provider] else { return nil }
        return try? await client.computeSnapshot(
            from: origin, to: destination, destinationPlaceID: destinationPlaceID
        )
    }

    // MARK: Recorder log (D-019)

    /// Append a line to the recorder log. Services call this for the
    /// events the recorder cannot see (permissions, GPS power state).
    func note(_ text: String) {
        log.append(LogEntry(time: .now, text: text))
        if log.count > Self.logCapacity {
            log.removeFirst(log.count - Self.logCapacity)
        }
        saveLog()
    }

    func clearLog() {
        log.removeAll()
        saveLog()
    }

    private func saveLog() {
        guard let logStorage else { return }
        let lines = log.map { "\($0.time.timeIntervalSince1970)|\($0.text)" }
        logStorage.set(lines, forKey: Self.logDefaultsKey)
    }

    private static func loadLog(from storage: UserDefaults?) -> [LogEntry] {
        guard let lines = storage?.stringArray(forKey: logDefaultsKey) else { return [] }
        return lines.compactMap { line in
            guard let bar = line.firstIndex(of: "|"),
                  let seconds = TimeInterval(line[..<bar])
            else { return nil }
            return LogEntry(
                time: Date(timeIntervalSince1970: seconds),
                text: String(line[line.index(after: bar)...])
            )
        }
    }

    private func handle(_ output: TripRecorder.Output?) {
        let previous = recorderState
        recorderState = recorder.state
        if previous == .idle, recorderState == .armed {
            samplesThisSegment = 0
            note("Armed: driving motion detected, GPS warming up")
        } else if previous == .armed, recorderState == .idle, output == nil {
            note("Disarmed: pedestrian motion before the car moved")
        }
        guard let output else { return }
        switch output {
        case .tripStarted(let departure):
            lastOutcome = "Recording"
            note("Recording started (departure \(Self.clock(departure)))")
            beginSnapshotFetch(departure: departure)
        case .tripDiscarded(let reason):
            let headline = reason == .tooShort ? "Trip too short to keep" : "Trip too brief to keep"
            lastOutcome = headline + endDetail
            note(lastOutcome ?? headline)
            clearPendingSnapshots()
        case .tripFinalized(let trip):
            persist(trip)
        }
    }

    /// "— ended by 3 min idle; 3 points over 0:41, 0.1 mi": the facts the
    /// discard thresholds were judged against, from the kit's summary.
    private var endDetail: String {
        var parts: [String] = []
        if let cause = recorder.lastEndCause {
            parts.append("ended by \(Self.label(cause))")
        }
        if let segment = recorder.lastSegment {
            parts.append(
                "\(segment.points) points over \(Format.duration(segment.duration)), \(Format.distance(segment.distanceM))"
            )
            if segment.rejectedPoints > 0 {
                parts.append("\(segment.rejectedPoints) inaccurate samples dropped")
            }
        }
        return parts.isEmpty ? "" : " — " + parts.joined(separator: "; ")
    }

    private static func label(_ cause: TripRecorder.EndCause) -> String {
        switch cause {
        case .idleTimeout: "3 min idle"
        case .pedestrianMotion: "walking away"
        case .gapSplit: "a gap in GPS"
        case .manualStop: "the Stop button"
        }
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Departure snapshots (FR-5/FR-6, "beat both")

    private func beginSnapshotFetch(departure: Date) {
        guard !providers.isEmpty, let originPoint = recorder.liveTrack.first else { return }
        snapshotFetch = Task { [weak self] in
            await self?.fetchSnapshots(originPoint: originPoint, departure: departure)
        }
    }

    private func fetchSnapshots(originPoint: TrackPoint, departure: Date) async {
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
            if targets.isEmpty, !places.isEmpty {
                note("Destination not predictable yet; asking with a notification")
                onDestinationUnknown?(places)
            }
            for targetID in targets {
                guard let place = places.first(where: { $0.id == targetID }) else { continue }
                await fetchAllPlans(from: originPoint.coordinate, to: place, label: place.name)
            }
        } catch {
            // No comparison for this trip — recording is never blocked
            // by the provider (FR-3).
        }
    }

    private func fetchAllPlans(from origin: Coordinate, to place: Place, label: String) async {
        for provider in availableProviders {
            guard let client = providers[provider] else { continue }
            if let snapshot = try? await client.computeSnapshot(
                from: origin, to: place.coordinate, destinationPlaceID: place.id
            ) {
                pendingSnapshots.append(snapshot)
                note("\(provider.displayName) plan fetched for \(label): ETA \(Format.duration(snapshot.trafficDuration))")
            } else {
                note("\(provider.displayName) plan for \(label) failed")
            }
        }
    }

    /// The one-tap pick (FR-6): fetch every provider's plan for a
    /// destination the user named, from wherever the drive currently is.
    /// No-op when idle or with no provider.
    func requestSnapshot(to placeID: UUID) {
        guard recorderState == .recording, !providers.isEmpty,
              let position = recorder.liveTrack.last
        else { return }
        snapshotFetch = Task { [weak self] in
            guard let self else { return }
            guard let place = try? self.context.fetch(FetchDescriptor<PlaceRecord>())
                .first(where: { $0.id == placeID })?.place()
            else { return }
            await self.fetchAllPlans(from: position.coordinate, to: place, label: "\(place.name) (your pick)")
        }
    }

    private func clearPendingSnapshots() {
        pendingSnapshots.removeAll()
        snapshotFetch = nil
    }

    /// A plan belongs to a finished drive when it was made for the place
    /// the drive ended at, or ends within `plannedArrivalRadiusM` of where
    /// the drive ended (a searched address, FR-20).
    static func snapshot(
        _ snapshot: PlanSnapshot,
        matchesArrivalAt end: Coordinate?,
        place arrived: Place?
    ) -> Bool {
        if let arrived, snapshot.destinationPlaceID == arrived.id { return true }
        guard let end, let planEnd = snapshot.destination else { return false }
        return Geo.distanceMeters(from: end, to: planEnd) <= plannedArrivalRadiusM
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

            // The plans whose destination matches where the drive actually
            // ended; mispredictions are simply dropped. The preferred
            // provider's is the primary plan (the one the driver saw); the
            // other provider's rides along as the alternate.
            let end = trip.points.last?.coordinate
            let arrived = end.flatMap { RouteMatcher.place(containing: $0, in: places) }
            let matching = pendingSnapshots.filter {
                Self.snapshot($0, matchesArrivalAt: end, place: arrived)
            }
            let wanted = preference().snapshotProvider
            let primary = matching.first { $0.provider == wanted } ?? matching.first
            let alt = matching.first { $0.provider != primary?.provider }
            enriched.snapshotID = primary?.id
            enriched.altSnapshotID = alt?.id

            let result = RouteMatcher.assign(
                trip: enriched, places: places, variants: variants,
                snapshot: primary, altSnapshot: alt
            )
            if let newVariant = result.newVariant {
                context.insert(VariantRecord(newVariant))
            } else if let variantID = result.variantID,
                      let record = variantRecords.first(where: { $0.id == variantID }) {
                record.tripCount += 1
            }
            for snapshot in [primary, alt].compactMap({ $0 }) {
                context.insert(try SnapshotRecord(snapshot))
            }
            context.insert(try TripRecord(result.trip))
            try context.save()
            lastOutcome = "Trip saved"
            let comparison = switch (primary, alt) {
            case (nil, _): "no plan to compare"
            case (let p?, nil): "vs. \(p.provider.displayName)"
            case (let p?, let a?): "vs. \(p.provider.displayName) and \(a.provider.displayName)"
            }
            note("Trip saved: \(Format.duration(trip.endedAt.timeIntervalSince(trip.startedAt))), \(Format.distance(trip.distanceM)), \(comparison)\(endDetailCauseOnly)")
        } catch {
            // Never lose a drive silently: surface the failure.
            lastOutcome = "Could not save trip: \(error.localizedDescription)"
            note(lastOutcome ?? "Could not save trip")
        }
    }

    private var endDetailCauseOnly: String {
        recorder.lastEndCause.map { "; ended by \(Self.label($0))" } ?? ""
    }
}
