import Foundation

/// The auto-recording state machine (SPEC §2.3): `idle → armed → recording →
/// finalized`. Pure and deterministic — all time comes from sample
/// timestamps, never the wall clock — so the entire lifecycle is testable
/// with synthetic streams. The app's LocationService feeds it converted
/// CLLocation/CMMotionActivity values; it never touches those types itself.
public struct TripRecorder: Sendable {
    // MARK: Inputs

    public enum MotionKind: String, Sendable {
        case automotive
        case walking
        case running
        case cycling
        case stationary
        case unknown
    }

    public enum MotionConfidence: Int, Sendable, Comparable {
        case low = 0
        case medium = 1
        case high = 2

        public static func < (lhs: MotionConfidence, rhs: MotionConfidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct MotionSample: Sendable {
        public var kind: MotionKind
        public var confidence: MotionConfidence
        public var timestamp: Date

        public init(kind: MotionKind, confidence: MotionConfidence, timestamp: Date) {
            self.kind = kind
            self.confidence = confidence
            self.timestamp = timestamp
        }
    }

    // MARK: Outputs

    public enum DiscardReason: String, Sendable {
        /// Shorter than the minimum distance — a parking-lot shuffle.
        case tooShort
        /// Briefer than the minimum duration, or no moving points at all.
        case tooBrief
    }

    public enum Output: Sendable, Equatable {
        /// Recording began; the date is the first retained point's timestamp.
        case tripStarted(Date)
        case tripFinalized(Trip)
        case tripDiscarded(DiscardReason)
    }

    /// Why the last recording ended. Reported alongside every finalize so
    /// a field test can say what cut a drive short (D-019).
    public enum EndCause: String, Sendable {
        /// Below walking speed for the whole idle window.
        case idleTimeout
        /// Walking/running/cycling motion, confirmed (see `Config`).
        case pedestrianMotion
        /// The location stream stopped for longer than `gapSplitDuration`.
        case gapSplit
        /// `stopRecording()` — the Stop button or app shutdown.
        case manualStop
    }

    /// What the last recording held after trimming — the numbers the
    /// discard thresholds were judged against.
    public struct SegmentSummary: Sendable, Equatable {
        public var points: Int
        public var duration: TimeInterval
        public var distanceM: Double
        /// Location samples refused by the accuracy filter during this
        /// armed/recording segment. A high count with few kept points means
        /// the GPS never settled, not that the drive was short.
        public var rejectedPoints: Int
    }

    // MARK: Configuration

    public struct Config: Sendable {
        /// Speed that counts as "driving" for the start trigger.
        public var startSpeedMps: Double = 4.5
        /// How long driving speed must be sustained to start recording.
        public var startSustain: TimeInterval = 30
        /// Alternative start trigger: displacement from where we armed —
        /// catches slow garage/side-street starts that never hit speed.
        public var startDisplacementM: Double = 500
        /// Below this speed a point counts as idle.
        public var endSpeedMps: Double = 1.0
        /// Continuous idle that ends the trip (a long red light must not).
        public var endIdleDuration: TimeInterval = 180
        /// Trips shorter than this are discarded.
        public var minTripDistanceM: Double = 800
        /// Trips briefer than this are discarded.
        public var minTripDuration: TimeInterval = 180
        /// Points with worse (or invalid, negative) accuracy are dropped.
        public var maxHorizontalAccuracyM: Double = 50
        /// A timestamp gap this large splits the trip (app was killed).
        public var gapSplitDuration: TimeInterval = 300
        /// How much pre-drive history the armed buffer retains.
        public var armedBufferDuration: TimeInterval = 600
        /// A pedestrian motion sample ends the trip at once only when no
        /// point at driving speed arrived within this window. Inside it the
        /// sample is a suspect — motion classification lags and misfires —
        /// and location has to confirm the walk.
        public var pedestrianEndGrace: TimeInterval = 30
        /// How long after a suspect pedestrian sample the track must stay
        /// below driving speed before the trip ends. A point at driving
        /// speed clears the suspicion.
        public var pedestrianEndConfirm: TimeInterval = 20

        public init() {}
    }

    public enum State: String, Sendable {
        case idle
        case armed
        case recording
        /// Recording, but the driver stopped the clock (D-069). No sample
        /// is kept and nothing can end the drive; only `resumeRecording`
        /// or `stopRecording` leaves this state.
        case paused
    }

    /// A span the driver excluded from the drive by pausing.
    public struct PauseSpan: Sendable, Equatable {
        public var startedAt: Date
        public var endedAt: Date

        public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

        public init(startedAt: Date, endedAt: Date) {
            self.startedAt = startedAt
            self.endedAt = endedAt
        }

        /// True when this pause sits between two consecutive samples —
        /// the pair that must contribute no distance and no moving time,
        /// because whatever happened in it is not part of the drive.
        func spans(from: Date, to: Date) -> Bool {
            startedAt >= from && startedAt <= to
        }
    }

    // MARK: Stored state

    public private(set) var state: State = .idle

    /// The points gathered so far in the current armed/recording segment —
    /// the live surface for origin lookup and the ghost race (FR-15).
    public var liveTrack: [TrackPoint] { buffer }

    /// When the current recording's first retained point was taken;
    /// nil unless a drive is under way. A paused drive still has a start —
    /// it is the clock that stopped, not the drive.
    public var recordingStartedAt: Date? {
        (state == .recording || state == .paused) ? buffer.first?.timestamp : nil
    }

    /// True while the driver has the clock stopped.
    public var isPaused: Bool { state == .paused }

    /// Seconds excluded from this drive so far, counting an open pause up
    /// to `date`. Every elapsed figure the app shows — the scoreboard, the
    /// ghost race — subtracts this, or a coffee stop reads as losing to
    /// the nav by the length of the coffee stop.
    public func pausedSeconds(at date: Date) -> TimeInterval {
        let closed = pauseSpans.reduce(0) { $0 + $1.duration }
        guard let pausedAt else { return closed }
        return closed + max(0, date.timeIntervalSince(pausedAt))
    }

    /// Time on this drive that counts, at `date`.
    public func drivingElapsed(at date: Date) -> TimeInterval {
        guard let start = recordingStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(start) - pausedSeconds(at: date))
    }

    /// Diagnostics for the most recent finalize (D-019).
    public private(set) var lastEndCause: EndCause?
    public private(set) var lastSegment: SegmentSummary?

    private let config: Config
    private let timezoneID: String

    private var buffer: [TrackPoint] = []
    private var movingSince: Date?
    private var lastMovingAt: Date?
    /// Last point at or above `startSpeedMps` while recording.
    private var lastDrivingAt: Date?
    /// A pedestrian motion sample seen while we were recently at driving
    /// speed; the walk is confirmed or dismissed by the next points.
    private var pedestrianSince: Date?
    private var rejectedPoints = 0
    private var source: Trip.Source = .auto
    /// Closed pauses in the current segment (D-069).
    private var pauseSpans: [PauseSpan] = []
    /// When the open pause began, while one is open.
    private var pausedAt: Date?
    /// Set on resume and cleared by the next sample, so the pause itself
    /// cannot look like the dead location stream `gapSplitDuration` is
    /// there to catch.
    private var resumedAt: Date?

    public init(timezoneID: String, config: Config = Config()) {
        self.timezoneID = timezoneID
        self.config = config
    }

    // MARK: Motion input

    public mutating func ingest(motion: MotionSample) -> Output? {
        switch state {
        case .idle:
            if motion.kind == .automotive, motion.confidence >= .medium {
                state = .armed
                buffer.removeAll()
                movingSince = nil
                rejectedPoints = 0
            }
            return nil
        case .armed:
            // Arming was a false alarm if we go pedestrian before moving.
            if motion.kind != .automotive, motion.kind != .unknown,
               motion.confidence >= .medium, movingSince == nil {
                state = .idle
                buffer.removeAll()
            }
            return nil
        case .recording:
            return ingestWhileRecording(motion: motion)
        case .paused:
            // Walking into the shop is the reason the driver paused. No
            // motion sample may arm, end or otherwise move a paused drive.
            return nil
        }
    }

    private mutating func ingestWhileRecording(motion: MotionSample) -> Output? {
        guard motion.confidence >= .medium else { return nil }
        switch motion.kind {
        case .automotive:
            pedestrianSince = nil
        case .walking, .running, .cycling:
            let drivingRecently = lastDrivingAt.map {
                motion.timestamp.timeIntervalSince($0) < config.pedestrianEndGrace
            } ?? false
            if drivingRecently {
                // Suspect only: we were at speed moments ago. Location
                // decides — see `ingestWhileRecording(_:)`.
                if pedestrianSince == nil { pedestrianSince = motion.timestamp }
            } else {
                return finalize(cause: .pedestrianMotion)
            }
        case .stationary, .unknown:
            // A car at a red light is stationary. The idle window ends the
            // trip, never one sample — D-019.
            break
        }
        return nil
    }

    // MARK: Location input

    public mutating func ingest(location point: TrackPoint) -> Output? {
        guard point.horizontalAccuracyM >= 0,
              point.horizontalAccuracyM <= config.maxHorizontalAccuracyM
        else {
            if state != .idle { rejectedPoints += 1 }
            return nil
        }

        switch state {
        case .idle:
            return nil
        case .armed:
            return ingestWhileArmed(point)
        case .recording:
            return ingestWhileRecording(point)
        case .paused:
            // Dropped, not buffered and not counted as rejected: the
            // driver said this is not the drive.
            return nil
        }
    }

    private mutating func ingestWhileArmed(_ point: TrackPoint) -> Output? {
        let speed = effectiveSpeed(of: point, after: buffer.last)
        buffer.append(point)
        let horizon = config.armedBufferDuration
        buffer.removeAll { point.timestamp.timeIntervalSince($0.timestamp) > horizon }

        if speed >= config.startSpeedMps {
            if movingSince == nil { movingSince = point.timestamp }
        } else if speed < config.endSpeedMps {
            movingSince = nil
        }

        let sustained = movingSince.map { point.timestamp.timeIntervalSince($0) >= config.startSustain } ?? false
        let displaced = buffer.first.map {
            Geo.distanceMeters(from: $0.coordinate, to: point.coordinate) >= config.startDisplacementM
        } ?? false

        guard sustained || displaced else { return nil }

        if sustained, let movingSince {
            buffer.removeAll { $0.timestamp < movingSince }
        }
        state = .recording
        source = .auto
        lastMovingAt = point.timestamp
        lastDrivingAt = speed >= config.startSpeedMps ? point.timestamp : nil
        pedestrianSince = nil
        return buffer.first.map { .tripStarted($0.timestamp) }
    }

    private mutating func ingestWhileRecording(_ point: TrackPoint) -> Output? {
        // A pause is not a dead stream, so the gap is measured from the
        // resume rather than from the last sample before the pause.
        if let since = resumedAt ?? buffer.last?.timestamp,
           point.timestamp.timeIntervalSince(since) >= config.gapSplitDuration {
            // The stream died (app killed, tunnel). Close out what we have;
            // the next automotive motion sample re-arms for the remainder.
            return finalize(cause: .gapSplit)
        }
        resumedAt = nil

        let speed = effectiveSpeed(of: point, after: buffer.last)
        buffer.append(point)
        if speed >= config.startSpeedMps {
            lastDrivingAt = point.timestamp
            pedestrianSince = nil
        }
        if speed >= config.endSpeedMps {
            lastMovingAt = point.timestamp
        } else if let lastMovingAt,
                  point.timestamp.timeIntervalSince(lastMovingAt) >= config.endIdleDuration {
            return finalize(cause: .idleTimeout)
        }
        if let pedestrianSince,
           point.timestamp.timeIntervalSince(pedestrianSince) >= config.pedestrianEndConfirm {
            // Walking pace ever since the suspect sample: the drive ended
            // when the walk began.
            return finalize(cause: .pedestrianMotion)
        }
        return nil
    }

    // MARK: Manual controls

    /// Manual record button: skips arming and the start triggers entirely.
    public mutating func startManualRecording(at date: Date) {
        state = .recording
        source = .manual
        buffer.removeAll()
        movingSince = nil
        lastMovingAt = date
        lastDrivingAt = nil
        pedestrianSince = nil
        rejectedPoints = 0
    }

    /// Pause button (D-069): stop the clock without ending the drive.
    /// Returns false when there was nothing to pause. No sample is kept
    /// while paused and nothing can end the drive, so a stop for fuel or
    /// a passenger neither splits the trip nor counts against the nav's
    /// plan.
    @discardableResult
    public mutating func pauseRecording(at date: Date) -> Bool {
        guard state == .recording else { return false }
        state = .paused
        pausedAt = date
        return true
    }

    /// Play button: the clock starts again and the drive continues, in
    /// the same trip. Returns false when nothing was paused.
    @discardableResult
    public mutating func resumeRecording(at date: Date) -> Bool {
        guard state == .paused, let pausedAt else { return false }
        pauseSpans.append(PauseSpan(startedAt: pausedAt, endedAt: max(pausedAt, date)))
        self.pausedAt = nil
        state = .recording
        // The drive resumes here, not wherever it left off: the idle
        // window must not end a drive over time the driver excluded, and
        // there is no pedestrian suspicion left to carry across a pause.
        lastMovingAt = date
        lastDrivingAt = nil
        pedestrianSince = nil
        resumedAt = date
        return true
    }

    /// Manual stop. Also the path the app uses on graceful shutdown.
    /// Works from a paused drive: the open pause closes first, so the
    /// seconds between the pause and the stop are excluded like any other.
    public mutating func stopRecording(at date: Date) -> Output? {
        if state == .paused, let pausedAt {
            pauseSpans.append(PauseSpan(startedAt: pausedAt, endedAt: max(pausedAt, date)))
            self.pausedAt = nil
            state = .recording
        }
        guard state == .recording else { return nil }
        return finalize(cause: .manualStop)
    }

    // MARK: Finalization

    private mutating func finalize(cause: EndCause) -> Output {
        let walkBegan = pedestrianSince
        let rejected = rejectedPoints
        let pauses = pauseSpans
        defer {
            state = .idle
            buffer.removeAll()
            movingSince = nil
            lastMovingAt = nil
            lastDrivingAt = nil
            pedestrianSince = nil
            rejectedPoints = 0
            source = .auto
            pauseSpans = []
            pausedAt = nil
            resumedAt = nil
        }
        lastEndCause = cause

        // Everything from the suspected walk onward is the walk, not the drive.
        if let walkBegan {
            buffer.removeAll { $0.timestamp >= walkBegan }
        }

        // Trim trailing idle: everything after the last moving point is
        // parking, not driving.
        var lastMovingIndex: Int?
        for i in buffer.indices {
            let speed = effectiveSpeed(of: buffer[i], after: i > 0 ? buffer[i - 1] : nil)
            if speed >= config.endSpeedMps { lastMovingIndex = i }
        }
        guard let lastMovingIndex, buffer.count >= 2 else {
            lastSegment = SegmentSummary(
                points: buffer.count,
                duration: span(of: buffer),
                distanceM: 0,
                rejectedPoints: rejected
            )
            return .tripDiscarded(.tooBrief)
        }
        let points = Array(buffer[0...lastMovingIndex])
        guard points.count >= 2, let first = points.first, let last = points.last else {
            lastSegment = SegmentSummary(
                points: points.count,
                duration: span(of: points),
                distanceM: 0,
                rejectedPoints: rejected
            )
            return .tripDiscarded(.tooBrief)
        }

        // Only pauses *inside* the retained drive. A pause the driver
        // never resumed begins at or after the last retained point, and
        // is trailing time like the parking the trimming above removed —
        // subtracting it would shorten a real drive by however long the
        // phone sat paused, and could discard it as too brief.
        let spans = pauses.filter { $0.startedAt >= first.timestamp && $0.startedAt < last.timestamp }
        let pausedTime = spans.reduce(0) { $0 + $1.duration }

        var distance = 0.0
        var movingTime = 0.0
        for i in 1..<points.count {
            let from = points[i - 1].timestamp
            let to = points[i].timestamp
            // The driver excluded whatever happened in a pause, so the
            // pair that brackets one contributes neither the straight
            // line across it nor the time it took.
            if spans.contains(where: { $0.spans(from: from, to: to) }) { continue }
            distance += Geo.distanceMeters(from: points[i - 1].coordinate, to: points[i].coordinate)
            if effectiveSpeed(of: points[i], after: points[i - 1]) >= config.endSpeedMps {
                movingTime += to.timeIntervalSince(from)
            }
        }
        let duration = max(0, last.timestamp.timeIntervalSince(first.timestamp) - pausedTime)
        lastSegment = SegmentSummary(
            points: points.count,
            duration: duration,
            distanceM: distance,
            rejectedPoints: rejected
        )
        guard duration >= config.minTripDuration else { return .tripDiscarded(.tooBrief) }
        guard distance >= config.minTripDistanceM else { return .tripDiscarded(.tooShort) }

        let trip = Trip(
            startedAt: first.timestamp,
            endedAt: last.timestamp,
            timezoneID: timezoneID,
            points: points,
            distanceM: distance,
            movingTime: movingTime,
            idleTime: max(0, duration - movingTime),
            pausedTime: pausedTime,
            source: source
        )
        return .tripFinalized(trip)
    }

    // MARK: Helpers

    /// The point's reported speed when valid, otherwise derived from the
    /// distance and time to the previous point.
    private func effectiveSpeed(of point: TrackPoint, after previous: TrackPoint?) -> Double {
        if point.speedMps >= 0 { return point.speedMps }
        guard let previous else { return 0 }
        let dt = point.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return 0 }
        return Geo.distanceMeters(from: previous.coordinate, to: point.coordinate) / dt
    }

    private func span(of points: [TrackPoint]) -> TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }
}
