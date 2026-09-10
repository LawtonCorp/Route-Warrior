import Foundation
import RouteWarriorKit

/// What the Plan tab shows of the recorder, and when (D-045, D-046).
/// Pure so the rules are testable without a screen.
enum HomeLayout {
    /// Record lives in the navigation bar, and only while there is
    /// nothing else that would start a drive: no destination (Go would),
    /// no drive in progress (Stop is on the recorder row). The recorder
    /// arming itself is not a drive yet, so Record stays for a missed
    /// detection.
    static func showsRecordButton(hasDestination: Bool, state: TripRecorder.State) -> Bool {
        state != .recording && !hasDestination
    }

    /// The one-line recorder row beneath the routes: shown while armed
    /// (a caption) or recording (Stop and the drive view). An idle
    /// recorder takes no space at all.
    static func showsRecorderRow(_ state: TripRecorder.State) -> Bool {
        state != .idle
    }

    /// The words on the recorder row (D-056). Armed says what it means
    /// for the driver — nothing to do — not how the recorder works.
    static func recorderCaption(_ state: TripRecorder.State) -> String {
        switch state {
        case .recording: "Rec"
        default: "Drive detected — recording starts on its own"
        }
    }
}
