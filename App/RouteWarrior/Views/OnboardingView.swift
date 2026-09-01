import SwiftUI

/// FR-18: educate before asking. Three pages — the payoff, the privacy
/// promise, then the permission primers in order. Shown once (tracked in
/// AppStorage); every prompt is preceded by its explanation.
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
            title: "Beat the nav. Prove it.",
            body: "Route Warrior records the routes you actually drive and compares them against Google's plan — every trip, hands-free. Find out when your shortcut really is faster."
        ) {
            Button("Continue") { page = 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    private var privacyPage: some View {
        pageLayout(
            icon: "lock.shield",
            title: "Your drives are yours.",
            body: "Everything stays on your iPhone and in your private iCloud. No accounts. No servers of ours. No analytics. The only thing that ever leaves your phone is the route request that makes the Google comparison possible."
        ) {
            Button("Continue") { page = 2 }
                .buttonStyle(.borderedProminent)
        }
    }

    private var permissionsPage: some View {
        pageLayout(
            icon: "location.circle",
            title: "Hands-free needs two permissions.",
            body: "Location records the route; Motion notices when a drive starts and ends. Allow \"While Using\" first — you can upgrade to \"Always\" in Settings for fully automatic recording, or skip it and use the manual Record button."
        ) {
            VStack(spacing: 12) {
                Button("Allow location") {
                    locationService.requestWhenInUseAuthorization()
                }
                .buttonStyle(.borderedProminent)
                Button("Start using Route Warrior") {
                    onboardingComplete = true
                }
            }
        }
    }

    private func pageLayout(
        icon: String,
        title: String,
        body bodyText: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
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
