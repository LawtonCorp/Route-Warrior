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
    }

    // MARK: Stored state

    public private(set) var state: State = .idle

    /// The points gathered so far in the current armed/recording segment —
    /// the live surface for origin lookup and the ghost race (FR-15).
    public var liveTrack: [TrackPoint] { buffer }

    /// When the current recording's first retained point was taken;
    /// nil unless recording.
    public var recordingStartedAt: Date? {
        state == .recording ? buffer.first?.timestamp : nil
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
        if let last = buffer.last,
           point.timestamp.timeIntervalSince(last.timestamp) >= config.gapSplitDuration {
            // The stream died (app killed, tunnel). Close out what we have;
            // the next automotive motion sample re-arms for the remainder.
            return finalize(cause: .gapSplit)
        }

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

    /// Manual stop. Also the path the app uses on graceful shutdown.
    public mutating func stopRecording() -> Output? {
        guard state == .recording else { return nil }
        return finalize(cause: .manualStop)
    }

    // MARK: Finalization

    private mutating func finalize(cause: EndCause) -> Output {
        let walkBegan = pedestrianSince
        let rejected = rejectedPoints
        defer {
            state = .idle
            buffer.removeAll()
            movingSince = nil
            lastMovingAt = nil
            lastDrivingAt = nil
            pedestrianSince = nil
            rejectedPoints = 0
            source = .auto
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

        var distance = 0.0
        var movingTime = 0.0
        for i in 1..<points.count {
            let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
            distance += Geo.distanceMeters(from: points[i - 1].coordinate, to: points[i].coordinate)
            if effectiveSpeed(of: points[i], after: points[i - 1]) >= config.endSpeedMps {
                movingTime += dt
            }
        }
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
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
