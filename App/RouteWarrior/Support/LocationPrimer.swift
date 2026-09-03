import CoreLocation
import SwiftUI
import UIKit

/// The one decision behind every "fix your location permission" surface
/// (onboarding, the Home card, Settings): what to ask for next, given what
/// iOS has granted and whether the one-shot Always prompt is already spent.
/// Pure so it is testable; the views only render the step (D-020).
enum LocationPrimer {
    enum Step: Equatable {
        /// Nothing granted yet: request While Using (iOS asks in two steps).
        case askWhileUsing
        /// While Using granted and the Always prompt not yet shown: ask.
        case askAlways
        /// While Using granted but the Always prompt already spent; only
        /// the system Settings app can change it now.
        case openSettingsForAlways
        /// Always granted: hands-free recording works.
        case done
        /// Denied or restricted: only Settings can help.
        case openSettingsForLocation
    }

    static func step(for status: CLAuthorizationStatus, alwaysRequested: Bool) -> Step {
        switch status {
        case .authorizedAlways: .done
        case .authorizedWhenInUse: alwaysRequested ? .openSettingsForAlways : .askAlways
        case .denied, .restricted: .openSettingsForLocation
        default: .askWhileUsing
        }
    }

    /// The plain-words consequence of the current grant. Nil when nothing
    /// needs saying (Always).
    static func warning(for status: CLAuthorizationStatus) -> String? {
        switch status {
        case .authorizedAlways:
            nil
        case .authorizedWhenInUse:
            "Location is set to While Using, so Route Rebel can only record a drive you start with the Record button while the app is open. Choose Always for hands-free recording."
        case .denied, .restricted:
            "Location is off, so Route Rebel cannot record drives. Turn it on in Settings and choose Always."
        default:
            "Location permission is needed to record drives — choose Always for hands-free recording."
        }
    }
}

/// The single control that moves the user to the next permission step.
/// Rendered as a plain row in Settings, a bordered button on the Home
/// card, and a prominent button in onboarding; hidden once Always is set.
struct LocationFixButton: View {
    enum Style {
        case row
        case bordered
        case prominent
    }

    @Environment(LocationService.self) private var locationService
    var style: Style = .row

    private var step: LocationPrimer.Step {
        LocationPrimer.step(
            for: locationService.authorizationStatus,
            alwaysRequested: locationService.alwaysRequested
        )
    }

    var body: some View {
        switch step {
        case .askWhileUsing:
            styled(Button("Allow location") { locationService.requestWhenInUseAuthorization() })
        case .askAlways:
            styled(Button("Change to Always") { locationService.requestAlwaysAuthorization() })
        case .openSettingsForAlways:
            styled(Link(
                "Open Settings and choose Always",
                destination: URL(string: UIApplication.openSettingsURLString)!
            ))
        case .openSettingsForLocation:
            styled(Link(
                "Turn on location in Settings",
                destination: URL(string: UIApplication.openSettingsURLString)!
            ))
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private func styled(_ control: some View) -> some View {
        switch style {
        case .row:
            control
        case .bordered:
            control.buttonStyle(.bordered).tint(Theme.google)
        case .prominent:
            control.buttonStyle(.borderedProminent).tint(Theme.google)
        }
    }
}
