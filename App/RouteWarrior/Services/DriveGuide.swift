import Foundation
import RouteWarriorKit

/// The drive view's navigator (D-052): feeds the live position to the
/// kit's guidance engine along the line being followed and hands its
/// callouts to the voice. It follows the departure plan until a reroute
/// lands, then the reroute — and never touches the snapshot the drive
/// is judged against, which the scoreboard reads on its own (D-010).
@MainActor
@Observable
final class DriveGuide {
    /// The plan whose steps are being followed right now.
    private(set) var following: PlanSnapshot
    private(set) var guidance: GuidanceEngine.Guidance?
    /// Every callout made, newest last; the recorder log and the tests
    /// read it.
    private(set) var announcements: [GuidanceEngine.Announcement] = []
    /// Silence the voice without losing the banner.
    var voiceEnabled = true

    private var engine: GuidanceEngine
    private let units: GuidanceEngine.Units
    private let voice: (any GuidanceSpeaking)?

    init(plan: PlanSnapshot, units: GuidanceEngine.Units, voice: (any GuidanceSpeaking)?) {
        following = plan
        self.units = units
        self.voice = voice
        var config = GuidanceEngine.Config()
        config.units = units
        engine = GuidanceEngine(steps: plan.steps, config: config)
    }

    /// True when the line being followed has maneuvers to speak of.
    var hasSteps: Bool { engine.hasSteps }

    /// "450 ft" to the maneuver ahead.
    var distanceText: String? {
        guidance.map { GuidanceEngine.distanceText($0.metersToManeuver, units: units) }
    }

    /// A reroute landed: follow it from here. The departure plan is
    /// untouched; the caller keeps judging against it.
    func follow(_ plan: PlanSnapshot) {
        guard plan.id != following.id || plan.steps != following.steps else { return }
        following = plan
        var config = GuidanceEngine.Config()
        config.units = units
        engine = GuidanceEngine(steps: plan.steps, config: config)
        guidance = nil
    }

    func ingest(position: Coordinate) {
        let announcement = engine.ingest(position: position)
        guidance = engine.guidance
        guard let announcement else { return }
        announcements.append(announcement)
        if voiceEnabled {
            voice?.speak(announcement.text)
        }
    }

    /// The units the phone reads in: miles and feet unless the locale
    /// is metric.
    nonisolated static func localUnits(locale: Locale = .current) -> GuidanceEngine.Units {
        locale.measurementSystem == .metric ? .metric : .imperial
    }
}
