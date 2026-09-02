import SwiftUI

/// FR-18: educate before asking. Three pages — the payoff, the privacy
/// promise, then the permission walk-through, which is driven by what iOS
/// has actually granted so it ends on Always, not on While Using (D-020).
/// Shown once (tracked in AppStorage); every prompt is preceded by its
/// explanation, and Motion is only requested once this is complete.
struct OnboardingView: View {
    @Environment(LocationService.self) private var locationService
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            valuePage.tag(0)
            privacyPage.tag(1)
            permissionsPage.tag(2)
        }
        .tabViewStyle(.page)
        .interactiveDismissDisabled()
    }

    private var valuePage: some View {
        pageLayout(
            icon: "flag.checkered",
            color: Theme.route,
            title: "Beat the nav. Prove it.",
            body: "Route Warrior records the routes you actually drive and compares them against Google's plan — every trip, hands-free. Find out when your shortcut really is faster."
        ) {
            Button("Continue") { page = 1 }
                .buttonStyle(.borderedProminent)
                .tint(Theme.route)
        }
    }

    private var privacyPage: some View {
        pageLayout(
            icon: "lock.shield",
            color: Theme.win,
            title: "Your drives are yours.",
            body: "Everything stays on your iPhone and in your private iCloud. No accounts. No servers of ours. No analytics. The only thing that ever leaves your phone is the route request that makes the Google comparison possible."
        ) {
            Button("Continue") { page = 2 }
                .buttonStyle(.borderedProminent)
                .tint(Theme.win)
        }
    }

    // MARK: Permissions, step by step

    private var step: LocationPrimer.Step {
        LocationPrimer.step(
            for: locationService.authorizationStatus,
            alwaysRequested: locationService.alwaysRequested
        )
    }

    private var permissionsPage: some View {
        pageLayout(
            icon: permissionIcon,
            color: permissionColor,
            title: permissionTitle,
            body: permissionBody
        ) {
            VStack(spacing: 12) {
                LocationFixButton(style: .prominent)
                switch step {
                case .askWhileUsing:
                    EmptyView()
                case .askAlways, .openSettingsForAlways:
                    Button("Keep While Using — I'll record manually") { finish() }
                case .done:
                    Button("Start using Route Warrior") { finish() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.win)
                case .openSettingsForLocation:
                    Button("Continue without recording") { finish() }
                }
            }
        }
    }

    private var permissionIcon: String {
        switch step {
        case .done: "checkmark.circle.fill"
        case .openSettingsForAlways, .openSettingsForLocation: "gearshape.fill"
        case .askWhileUsing, .askAlways: "location.circle"
        }
    }

    private var permissionColor: Color {
        switch step {
        case .done: Theme.win
        case .openSettingsForLocation: Theme.recording
        case .askWhileUsing, .askAlways, .openSettingsForAlways: Theme.google
        }
    }

    private var permissionTitle: String {
        switch step {
        case .askWhileUsing: "Hands-free needs location set to Always."
        case .askAlways: "One more step: Always."
        case .openSettingsForAlways: "Always is still off."
        case .done: "You're set."
        case .openSettingsForLocation: "Location is off."
        }
    }

    private var permissionBody: String {
        switch step {
        case .askWhileUsing:
            "Route Warrior records drives in the background, so iPhone must allow location Always. With only While Using, it can't follow a drive once the phone locks. iPhone asks in two steps: While Using first, then Always."
        case .askAlways:
            "You allowed While Using. That records only drives you start with the Record button while the app is open. Tap Change to Always, then choose \"Change to Always Allow\" so drives record themselves."
        case .openSettingsForAlways:
            "iPhone asks about Always only once. To record hands-free, open Settings → Route Warrior → Location and choose Always. You can do this any time from the Settings tab."
        case .done:
            "Location is set to Always, so drives record themselves. Next, iPhone asks for Motion & Fitness — that's how Route Warrior notices a drive starting without running GPS all day."
        case .openSettingsForLocation:
            "Route Warrior cannot record without location. Open Settings → Route Warrior → Location and choose Always."
        }
    }

    private func finish() {
        onboardingComplete = true
        locationService.enableMotionDetection()
    }

    private func pageLayout(
        icon: String,
        color: Color,
        title: String,
        body bodyText: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(color)
                .frame(width: 136, height: 136)
                .background(color.opacity(0.12), in: Circle())
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(bodyText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            actions()
            Spacer().frame(height: 40)
        }
        .padding()
    }
}
