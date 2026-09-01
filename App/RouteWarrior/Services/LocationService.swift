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

    private let manager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let pipeline: RecordingPipeline
    private var highPowerActive = false

    init(pipeline: RecordingPipeline) {
        self.pipeline = pipeline
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        manager.startMonitoringSignificantLocationChanges()
        startMotionUpdates()
        syncPowerMode()
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: Sample forwarding

    func forward(location point: TrackPoint) {
        pipeline.ingest(location: point)
        syncPowerMode()
    }

    func forward(motion sample: TripRecorder.MotionSample) {
        pipeline.ingest(motion: sample)
        syncPowerMode()
    }

    private func startMotionUpdates() {
        guard motionAvailable else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let sample = TripRecorder.MotionSample(
                kind: Self.kind(of: activity),
                confidence: Self.confidence(of: activity),
                timestamp: Date(timeInterval: activity.timestamp - ProcessInfo.processInfo.systemUptime, since: .now)
            )
            Task { @MainActor [weak self] in
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
            }
        case .armed, .recording:
            if !highPowerActive {
                manager.allowsBackgroundLocationUpdates =
                    manager.authorizationStatus == .authorizedAlways
                manager.startUpdatingLocation()
                highPowerActive = true
            }
        }
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
        Task { @MainActor [weak self] in
            for point in points {
                self?.forward(location: point)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.authorizationStatus = status
            self?.syncPowerMode()
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
}
