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
    /// Which departure the in-flight fetch belongs to (D-055). A plan
    /// that lands after the driver named a destination, after the drive
    /// ended, or after a newer request began is not this drive's and is
    /// dropped: the map draws one destination, the one the driver chose.
    private var snapshotGeneration = 0

    private var recorder: TripRecorder
    private let context: ModelContext
    private let timezoneID: String
    /// Every routing provider this build can reach, by the provider its
    /// snapshots carry.
    private let providers: [PlanSnapshot.Provider: any RoutesProviding]
    /// Whose plan the driver sees — the primary snapshot on the trip.
    private let preference: @MainActor () -> MapProvider
    /// The driver's tier, read at every request (D-050): a purchase
    /// mid-drive takes effect on the next departure without a restart.
    private let tier: @MainActor () -> TierPolicy.Tier
    private let policy: TierPolicy
    private let logStorage: UserDefaults?
    private var pendingSnapshots: [PlanSnapshot] = []
    /// The driver's own route for this drive, when they picked one
    /// (FR-25, D-066): drawn by the drive view, watched for off-route,
    /// and written to the trip as the pick — never as the baseline.
    private var pendingChosenRoute: ChosenRoute?
    /// Whether to end a planned drive on arrival (D-038), read per sample
    /// so a Settings change applies to the drive in progress.
    private let arrivalStop: @MainActor () -> Bool
    /// The driver's "pause becomes a stop after" setting (D-072).
    private let pauseWatch: @MainActor () -> PauseWatch.Config
    /// When the current pause's countdown began — the pause itself, or
    /// the last "Still here". Deliberately apart from the recorder's own
    /// paused total, which is the drive's measurement and must never be
    /// reset by a driver answering a question.
    private var pauseCountdownFrom: Date?
    private var arrivalDetector = ArrivalDetector()
    private var samplesThisSegment = 0
    /// D-045: a manual Record has no plan, so it predicts its destination
    /// the way an auto-detected drive does — as soon as it has a first
    /// point to predict from.
    private var predictOnFirstSample = false

    /// FR-6 fallback: fired when a trip starts but no destination clears
    /// the confidence bar. The app answers with a one-tap picker
    /// (notification); the pick calls `requestSnapshot(to:)`.
    var onDestinationUnknown: (@MainActor ([Place]) -> Void)?
    /// Ask, out of the app, whether the drive is still going (D-072).
    /// The Int is the limit in minutes, for the wording.
    var onPauseStillThere: (@MainActor (Int) -> Void)?
    /// The question is over — withdraw it wherever it was asked.
    var onPauseAnswered: (@MainActor () -> Void)?
    /// True while "Still there?" is waiting for an answer in the app.
    private(set) var pauseNeedsAnswer = false

    init(
        context: ModelContext,
        timezoneID: String = TimeZone.current.identifier,
        routesProvider: (any RoutesProviding)? = nil,
        providers: [PlanSnapshot.Provider: any RoutesProviding] = [:],
        preference: @escaping @MainActor () -> MapProvider = { MapProvider.default },
        arrivalStop: @escaping @MainActor () -> Bool = { false },
        pauseWatch: @escaping @MainActor () -> PauseWatch.Config = { PauseWatch.Config() },
        tier: @escaping @MainActor () -> TierPolicy.Tier = { .pro },
        policy: TierPolicy = TierPolicy(),
        logStorage: UserDefaults? = nil
    ) {
        self.context = context
        self.timezoneID = timezoneID
        self.tier = tier
        self.policy = policy
        var all = providers
        if let routesProvider {
            // v1 spelling: a single Google provider.
            all[.googleRoutes] = routesProvider
        }
        self.providers = all
        self.preference = preference
        self.arrivalStop = arrivalStop
        self.pauseWatch = pauseWatch
        self.logStorage = logStorage
        self.recorder = TripRecorder(timezoneID: timezoneID)
        self.log = Self.loadLog(from: logStorage)
    }

    var isRecording: Bool { recorderState == .recording }
    /// The clock is stopped but the drive is not over (D-069).
    var isPaused: Bool { recorderState == .paused }
    /// A drive is under way, running or paused. The controls and the live
    /// trail key off this; `isRecording` alone would make them vanish the
    /// moment the driver pressed pause.
    var isDriveInProgress: Bool { isRecording || isPaused }
    var liveTrack: [TrackPoint] { recorder.liveTrack }
    var recordingStartedAt: Date? { recorder.recordingStartedAt }

    /// Seconds excluded from this drive so far (D-069).
    func pausedSeconds(at date: Date = .now) -> TimeInterval {
        recorder.pausedSeconds(at: date)
    }

    /// Time on this drive that counts — what the scoreboard and the ghost
    /// race are built from, so a pause freezes them instead of running up
    /// a loss against the nav's plan.
    func drivingElapsed(at date: Date = .now) -> TimeInterval {
        recorder.drivingElapsed(at: date)
    }
    /// Providers this build can ask, Apple first (the default map).
    var availableProviders: [PlanSnapshot.Provider] {
        [PlanSnapshot.Provider.appleMaps, .googleRoutes].filter { providers[$0] != nil }
    }

    /// Providers this driver's tier is asked for a plan (D-050): the free
    /// tier gets Apple's, Pro gets every one the build can reach.
    var snapshotProviders: [PlanSnapshot.Provider] {
        policy.snapshotProviders(for: tier(), available: availableProviders)
    }
    /// The plans held for the current drive (for the drive view).
    var plansForCurrentDrive: [PlanSnapshot] { pendingSnapshots }

    /// One of the driver's own routes, chosen on the Plan tab (D-066).
    struct ChosenRoute: Equatable, Sendable {
        let variantID: UUID
        let polyline: Polyline
    }

    /// The route the driver chose to drive this time, if any.
    var chosenRouteForCurrentDrive: ChosenRoute? { pendingChosenRoute }

    func ingest(location point: TrackPoint) {
        // Paused samples are not this segment's: counting them would put
        // a number in the recorder log for points that were dropped.
        if recorder.state != .idle, !recorder.isPaused {
            samplesThisSegment += 1
            if samplesThisSegment == 1 {
                note("First location sample since arming (±\(Int(point.horizontalAccuracyM)) m, \(Int(max(0, point.speedMps))) m/s)")
            }
        }
        // Arrival ends a planned drive before the recorder's own idle
        // window would, so the trip's end is the kerb, not the kerb plus
        // however long the phone sat in the cup holder (D-038).
        if recorder.state == .recording, arrivalStop(),
           let destination = pendingSnapshots.first?.destination,
           arrivalDetector.ingest(point, destination: destination) == .arrived {
            note("Arrived at the destination — recording stopped")
            arrivalDetector.reset()
            handle(recorder.stopRecording(at: point.timestamp))
            return
        }
        if recorder.isPaused {
            // Samples still arrive while paused (the GPS stays on,
            // D-069) and the recorder drops them — but they are the only
            // clock that runs with the app off screen, so the pause
            // deadline is read off them (D-072).
            checkPause(at: point.timestamp)
            return
        }
        handle(recorder.ingest(location: point))
        if predictOnFirstSample, recorder.state == .recording, let first = recorder.liveTrack.first {
            predictOnFirstSample = false
            note("Predicting the destination of the manual recording")
            beginSnapshotFetch(departure: first.timestamp)
        }
    }

    func ingest(motion sample: TripRecorder.MotionSample) {
        handle(recorder.ingest(motion: sample))
    }

    func startManualRecording() {
        recorder.startManualRecording(at: .now)
        recorderState = recorder.state
        samplesThisSegment = 0
        predictOnFirstSample = true
        lastOutcome = "Recording (manual)"
        note("Recording started by the Record button")
    }

    /// FR-20: the driver chose a destination and saw the plans. Recording
    /// starts now (unless a drive is already being recorded) and those
    /// plans become the departure snapshots — no second fetch.
    func startPlannedDrive(with snapshots: [PlanSnapshot], choosingRoute chosen: ChosenRoute? = nil) {
        if recorder.state == .paused {
            // Go on a paused drive continues it. Starting again would
            // throw away the track already driven (D-069).
            resumeRecording(at: .now)
        } else if recorder.state != .recording {
            recorder.startManualRecording(at: .now)
            recorderState = recorder.state
            samplesThisSegment = 0
        }
        // The driver named the destination: any guess still being fetched
        // for an auto-detected start is superseded (D-055).
        supersedePendingFetch()
        pendingSnapshots = snapshots
        pendingChosenRoute = chosen
        predictOnFirstSample = false
        arrivalDetector.reset()
        lastOutcome = "Recording (planned)"
        let route = chosen.map { _ in ", driving your own route" } ?? ""
        note("Recording started from the plan screen with \(snapshots.count) plan(s)\(route)")
    }

    /// A newer intent replaces whatever fetch was in flight: its answer,
    /// when it lands, is checked against the generation and dropped.
    private func supersedePendingFetch() {
        snapshotGeneration += 1
        snapshotFetch?.cancel()
        snapshotFetch = nil
    }

    /// D-044: the driver tapped Go while the plans were still loading.
    /// A plan requested from the departure point before the drive began
    /// is still the departure snapshot when it lands a few seconds later,
    /// so it is adopted — but only into a drive that has none. A drive
    /// that already carries plans keeps them (D-010: never replaced).
    func adoptDeparturePlans(_ snapshots: [PlanSnapshot]) {
        guard isDriveInProgress, pendingSnapshots.isEmpty, !snapshots.isEmpty else { return }
        supersedePendingFetch()
        pendingSnapshots = snapshots
        arrivalDetector.reset()
        note("\(snapshots.count) plan(s) arrived after departure and became the baseline")
    }

    func stopManualRecording(at date: Date = .now) {
        endPauseWatch()
        handle(recorder.stopRecording(at: date))
    }

    /// Pause button (D-069). The drive stays open and the clock stops;
    /// no sample is kept and nothing can end the drive until the driver
    /// says so.
    func pauseRecording(at date: Date = .now) {
        guard recorder.pauseRecording(at: date) else { return }
        recorderState = recorder.state
        pauseCountdownFrom = date
        pauseNeedsAnswer = false
        lastOutcome = "Paused"
        note("Recording paused — the clock and the track stop until you resume")
    }

    /// Play button. The same drive continues; the paused seconds are
    /// excluded from it.
    func resumeRecording(at date: Date = .now) {
        let excluded = recorder.pausedSeconds(at: date)
        guard recorder.resumeRecording(at: date) else { return }
        recorderState = recorder.state
        endPauseWatch()
        lastOutcome = "Recording"
        note("Recording resumed — \(Format.duration(excluded)) excluded from this drive so far")
    }

    /// How long a paused drive may sit before it asks, and before it
    /// stops itself (D-072). Called from every arriving sample — which is
    /// what keeps it running with the screen off — and from a timer while
    /// the app is on screen and the phone too still to produce one.
    func checkPause(at date: Date = .now) {
        guard isPaused, let from = pauseCountdownFrom else { return }
        let config = pauseWatch()
        switch PauseWatch.state(pausedFor: date.timeIntervalSince(from), config: config) {
        case .waiting:
            break
        case .shouldAsk:
            // Asked once per lease, not once per sample.
            guard !pauseNeedsAnswer else { return }
            pauseNeedsAnswer = true
            note("Paused \(Format.duration(config.askAfter)) — asking whether the drive is still going")
            onPauseStillThere?(Int((config.limit / 60).rounded()))
        case .shouldStop:
            // Nothing driven is lost: a pause that was never resumed is
            // trailing time (D-069), so the trip ends where it paused.
            note("Paused \(Format.duration(config.limit)) with no answer — the drive was stopped and saved, ending where you paused")
            endPauseWatch()
            handle(recorder.stopRecording(at: date))
        }
    }

    /// "Still here" — the pause gets a fresh lease rather than ending.
    /// The drive's own paused total keeps running; this only defers the
    /// stop and the next question.
    func keepPaused(at date: Date = .now) {
        guard isPaused else { return }
        pauseCountdownFrom = date
        pauseNeedsAnswer = false
        onPauseAnswered?()
        note("Still there — the pause continues")
    }

    /// The question was dismissed without an answer. The lease is not
    /// renewed, so the drive still stops itself on time.
    func dismissPauseQuestion() {
        pauseNeedsAnswer = false
        onPauseAnswered?()
    }

    private func endPauseWatch() {
        pauseCountdownFrom = nil
        guard pauseNeedsAnswer else { return }
        pauseNeedsAnswer = false
        onPauseAnswered?()
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
        for provider in snapshotProviders {
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
        case let .badResponse(status, detail):
            return detail.isEmpty ? "HTTP \(status)" : "HTTP \(status) — \(detail)"
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

    /// The recorder log answers "why is this drive shorter than my
    /// afternoon" without the driver having to remember pausing.
    private func pausedDetail(_ trip: Trip) -> String {
        guard trip.pausedTime > 0 else { return "" }
        return " (\(Format.duration(trip.pausedTime)) paused, excluded)"
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
        guard !snapshotProviders.isEmpty, let originPoint = recorder.liveTrack.first else { return }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        snapshotFetch = Task { [weak self] in
            await self?.fetchSnapshots(originPoint: originPoint, departure: departure, generation: generation)
        }
    }

    private func fetchSnapshots(originPoint: TrackPoint, departure: Date, generation: Int) async {
        do {
            // In the driver's own order (D-074): the notification offers
            // the first few, and those should be the ones they put at the
            // top rather than the ones they happened to save first.
            let places = try context.fetch(PlaceOrder.fetchDescriptor).map { $0.place() }
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
                await fetchAllPlans(from: originPoint.coordinate, to: place, label: place.name, generation: generation)
            }
        } catch {
            // No comparison for this trip — recording is never blocked
            // by the provider (FR-3).
        }
    }

    private func fetchAllPlans(from origin: Coordinate, to place: Place, label: String, generation: Int) async {
        for provider in snapshotProviders {
            guard let client = providers[provider] else { continue }
            let snapshot = try? await client.computeSnapshot(
                from: origin, to: place.coordinate, destinationPlaceID: place.id
            )
            guard generation == snapshotGeneration else {
                note("\(provider.displayName) plan for \(label) arrived after the destination changed — dropped")
                return
            }
            if let snapshot {
                pendingSnapshots.append(snapshot)
                note("\(provider.displayName) plan fetched for \(label): ETA \(Format.duration(snapshot.trafficDuration))")
            } else {
                note("\(provider.displayName) plan for \(label) failed")
            }
        }
    }

    /// The one-tap pick (FR-6): fetch every provider's plan for a
    /// destination the user named, from wherever the drive currently is.
    /// The named destination replaces any guess (D-055): plans for other
    /// places are dropped, and a plan already held for this place is
    /// kept rather than fetched again from a later point. No-op when
    /// idle or with no provider.
    func requestSnapshot(to placeID: UUID) {
        guard recorderState == .recording, !snapshotProviders.isEmpty,
              let position = recorder.liveTrack.last
        else { return }
        supersedePendingFetch()
        pendingSnapshots.removeAll { $0.destinationPlaceID != placeID }
        guard pendingSnapshots.isEmpty else {
            note("Destination confirmed; keeping the plan already fetched for it")
            return
        }
        let generation = snapshotGeneration
        snapshotFetch = Task { [weak self] in
            guard let self else { return }
            guard let place = try? self.context.fetch(FetchDescriptor<PlaceRecord>())
                .first(where: { $0.id == placeID })?.place()
            else { return }
            await self.fetchAllPlans(
                from: position.coordinate, to: place, label: "\(place.name) (your pick)", generation: generation
            )
        }
    }

    private func clearPendingSnapshots() {
        pendingSnapshots.removeAll()
        pendingChosenRoute = nil
        // A plan still in flight for a drive that has ended belongs to
        // no drive (D-055).
        supersedePendingFetch()
        predictOnFirstSample = false
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
            let record = try TripRecord(result.trip)
            // The pick is the driver's annotation; `variantID` above is
            // the matcher's answer. Both are kept (D-066).
            record.chosenVariantID = pendingChosenRoute?.variantID
            context.insert(record)
            try context.save()
            lastOutcome = "Trip saved"
            let comparison = switch (primary, alt) {
            case (nil, _): "no plan to compare"
            case (let p?, nil): "vs. \(p.provider.displayName)"
            case (let p?, let a?): "vs. \(p.provider.displayName) and \(a.provider.displayName)"
            }
            note("Trip saved: \(Format.duration(trip.duration)), \(Format.distance(trip.distanceM))\(pausedDetail(trip)), \(comparison)\(endDetailCauseOnly)")
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
