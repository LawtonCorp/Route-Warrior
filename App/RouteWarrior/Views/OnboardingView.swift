import SwiftUI

/// FR-18: educate before asking. Three pages — the payoff, the privacy
/// promise, then the permission walk-through, which is driven by what iOS
/// has actually granted so it ends on Always, not on While Using (D-020).
/// Shown once (tracked in AppStorage); every prompt is preceded by its
/// explanation, and Motion is only requested once this is complete.
struct OnboardingView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(MapSettings.self) private var mapSettings
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var page = 0

    /// The provider page exists only when there is a choice (FR-19): a
    /// keyless build has Apple alone and skips it.
    private var offersProviderChoice: Bool { mapSettings.availableProviders.count > 1 }
    private var permissionsTag: Int { offersProviderChoice ? 3 : 2 }

    var body: some View {
        TabView(selection: $page) {
            valuePage.tag(0)
            privacyPage.tag(1)
            if offersProviderChoice {
                providerPage.tag(2)
            }
            permissionsPage.tag(permissionsTag)
        }
        .tabViewStyle(.page)
        .interactiveDismissDisabled()
    }

    // MARK: Whose routes?

    private var providerPage: some View {
        pageLayout(
            icon: "map.fill",
            color: Theme.route,
            title: "Whose routes do you want to beat?",
            body: "Pick the map and routes you see inside Route Rebel. Both providers' plans are compared on every drive; this only chooses the map you look at. Change it any time in Settings."
        ) {
            VStack(spacing: 12) {
                ForEach(mapSettings.availableProviders, id: \.self) { provider in
                    Button {
                        mapSettings.select(provider)
                    } label: {
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            if mapSettings.provider == provider {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .frame(maxWidth: 280)
                    }
                    .buttonStyle(.bordered)
                    .tint(mapSettings.provider == provider ? Theme.route : .secondary)
                }
                Button("Continue") { page = permissionsTag }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.route)
            }
        }
    }

    private var valuePage: some View {
        pageLayout(
            icon: "flag.checkered",
            color: Theme.route,
            title: "Beat the nav. Prove it.",
            body: "Route Rebel records the routes you actually drive and compares them against Google's plan — every trip, hands-free. Find out when your shortcut really is faster."
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
            Button("Continue") { page = offersProviderChoice ? 2 : permissionsTag }
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
                    Button("Start using Route Rebel") { finish() }
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
            "Route Rebel records drives in the background, so iPhone must allow location Always. With only While Using, it can't follow a drive once the phone locks. iPhone asks in two steps: While Using first, then Always."
        case .askAlways:
            "You allowed While Using. That records only drives you start with the Record button while the app is open. Tap Change to Always, then choose \"Change to Always Allow\" so drives record themselves."
        case .openSettingsForAlways:
            "iPhone asks about Always only once. To record hands-free, open Settings → Route Rebel → Location and choose Always. You can do this any time from the Settings tab."
        case .done:
            "Location is set to Always, so drives record themselves. Next, iPhone asks for Motion & Fitness — that's how Route Rebel notices a drive starting without running GPS all day."
        case .openSettingsForLocation:
            "Route Rebel cannot record without location. Open Settings → Route Rebel → Location and choose Always."
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
