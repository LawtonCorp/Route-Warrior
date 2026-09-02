import CoreLocation
import CoreMotion
import Foundation
import RouteWarriorKit

/// The only place CLLocation and CMMotionActivity exist: converts them to
/// kit value types and forwards to the pipeline (D-009). Also owns the
/// power tiering — significant-change + motion while idle, full-rate GPS
/// only while armed or recording (NFR-3).
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var motionAvailable = CMMotionActivityManager.isActivityAvailable()
    private(set) var motionAuthorization: CMAuthorizationStatus = CMMotionActivityManager.authorizationStatus()
    /// iOS shows the "Change to Always Allow" prompt once per install; after
    /// that only the Settings app can change it, so the UI must know the
    /// prompt is spent (D-020).
    private(set) var alwaysRequested = UserDefaults.standard.bool(forKey: "alwaysLocationRequested")
    private static let alwaysRequestedKey = "alwaysLocationRequested"
    private var motionUpdatesActive = false
    /// The most recent fix from any source — centres the New Place map at
    /// city scale instead of the whole country (D-021).
    private(set) var lastKnownCoordinate: Coordinate?

    private let manager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let pipeline: RecordingPipeline
    private let ghostRace: GhostRaceCoordinator?
    private var raceActive = false
    private var highPowerActive = false

    init(pipeline: RecordingPipeline, ghostRace: GhostRaceCoordinator? = nil) {
        self.pipeline = pipeline
        self.ghostRace = ghostRace
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        pipeline.note("App launched — location: \(Self.label(authorizationStatus)); motion: \(Self.label(motionAuthorization))")
        manager.startMonitoringSignificantLocationChanges()
        // FR-18: the Motion prompt waits for onboarding to explain it; the
        // onboarding flow calls `enableMotionDetection()` when it finishes.
        if UserDefaults.standard.bool(forKey: "onboardingComplete") {
            startMotionUpdates()
        }
        syncPowerMode()
    }

    /// Starts motion activity updates (and, the first time, the system
    /// Motion & Fitness prompt). Idempotent.
    func enableMotionDetection() {
        startMotionUpdates()
    }

    /// One fix for the UI when no drive is on; iOS answers through the
    /// normal delegate path (or `didFailWithError`, which we ignore).
    func requestOneShotLocation() {
        guard !highPowerActive else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        manager.requestLocation()
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        alwaysRequested = true
        UserDefaults.standard.set(true, forKey: Self.alwaysRequestedKey)
        pipeline.note("Asked for Always location")
        manager.requestAlwaysAuthorization()
    }

    // MARK: Sample forwarding

    func forward(location point: TrackPoint) {
        pipeline.ingest(location: point)
        syncGhostRace()
        syncPowerMode()
    }

    /// The ghost race rides the recording lifecycle: begin on the first
    /// recorded sample, feed the live track, end when the trip does (FR-15).
    private func syncGhostRace() {
        guard let ghostRace else { return }
        if pipeline.recorderState == .recording, let startedAt = pipeline.recordingStartedAt {
            if !raceActive {
                ghostRace.tripBegan()
                raceActive = true
            }
            ghostRace.ingest(track: pipeline.liveTrack, startedAt: startedAt)
        } else if raceActive {
            ghostRace.tripEnded()
            raceActive = false
        }
    }

    func forward(motion sample: TripRecorder.MotionSample) {
        pipeline.ingest(motion: sample)
        syncPowerMode()
    }

    private func startMotionUpdates() {
        guard motionAvailable, !motionUpdatesActive else { return }
        motionUpdatesActive = true
        pipeline.note("Motion detection on (\(Self.label(motionAuthorization)))")
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let sample = TripRecorder.MotionSample(
                kind: Self.kind(of: activity),
                confidence: Self.confidence(of: activity),
                timestamp: Date(timeInterval: activity.timestamp - ProcessInfo.processInfo.systemUptime, since: .now)
            )
            let authorization = CMMotionActivityManager.authorizationStatus()
            Task { @MainActor [weak self] in
                self?.motionAuthorization = authorization
                self?.forward(motion: sample)
            }
        }
    }

    /// Full-rate GPS is expensive; run it only while a drive might be on.
    private func syncPowerMode() {
        switch pipeline.recorderState {
        case .idle:
            if highPowerActive {
                manager.stopUpdatingLocation()
                highPowerActive = false
                pipeline.note("GPS off (idle)")
            }
        case .armed, .recording:
            applyBackgroundPolicy()
            if !highPowerActive {
                manager.startUpdatingLocation()
                highPowerActive = true
                let background = manager.allowsBackgroundLocationUpdates ? "continues when locked" : "foreground only"
                pipeline.note("GPS on — \(Self.label(authorizationStatus)), \(background)")
            }
        }
    }

    /// Background delivery needs the `location` background mode (declared
    /// in project.yml) plus any location authorization: a When-In-Use app
    /// keeps the updates it started in the foreground, under the system's
    /// blue indicator. Gating this on Always (as v1 did) meant a manual
    /// recording lost GPS the moment the phone locked — D-019.
    private func applyBackgroundPolicy() {
        let status = manager.authorizationStatus
        let authorized = status == .authorizedAlways || status == .authorizedWhenInUse
        manager.allowsBackgroundLocationUpdates = authorized
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.map { location in
            TrackPoint(
                coordinate: Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                timestamp: location.timestamp,
                speedMps: location.speed,
                courseDegrees: location.course,
                horizontalAccuracyM: location.horizontalAccuracy
            )
        }
        let latest = points.last?.coordinate
        Task { @MainActor [weak self] in
            if let latest { self?.lastKnownCoordinate = latest }
            for point in points {
                self?.forward(location: point)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            let changed = self.authorizationStatus != status
            self.authorizationStatus = status
            if changed {
                self.pipeline.note("Location permission: \(Self.label(status))")
            }
            if self.highPowerActive { self.applyBackgroundPolicy() }
            self.syncPowerMode()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (no fix yet) are normal; the recorder's
        // accuracy filter handles quality. Nothing to do.
    }

    // MARK: Conversion

    private static func kind(of activity: CMMotionActivity) -> TripRecorder.MotionKind {
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }

    private static func confidence(of activity: CMMotionActivity) -> TripRecorder.MotionConfidence {
        switch activity.confidence {
        case .high: return .high
        case .medium: return .medium
        default: return .low
        }
    }

    static func label(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not set"
        }
    }

    static func label(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not asked yet"
        }
    }
}
