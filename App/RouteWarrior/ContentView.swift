import SwiftUI

/// The root (D-053): onboarding, then the Terms-changed screen once per
/// new Terms version, then the app.
struct ContentView: View {
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(MapSettings.self) private var mapSettings
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage(Legal.acceptedTermsKey) private var acceptedTerms = ""

    var body: some View {
        switch RootRoute.route(onboardingComplete: onboardingComplete, acceptedTerms: acceptedTerms) {
        case .onboarding:
            OnboardingView()
        case .termsUpdate:
            TermsUpdateView()
        case .app:
            TabView {
                HomeView()
                    .tabItem { Label(RootTab.route.title, systemImage: RootTab.route.symbol) }
                TripsView()
                    .tabItem { Label(RootTab.trips.title, systemImage: RootTab.trips.symbol) }
                PlacesView()
                    .tabItem { Label(RootTab.places.title, systemImage: RootTab.places.symbol) }
                SettingsView()
                    .tabItem { Label(RootTab.settings.title, systemImage: RootTab.settings.symbol) }
            }
            // While the app is on screen a paused phone can sit still
            // enough to produce no location samples at all, and samples
            // are what carry the pause deadline otherwise (D-072). A
            // `.task` rather than a `Timer` publisher: the publisher is
            // a stored property of a struct that SwiftUI re-creates, so
            // every re-render would resubscribe and restart the
            // countdown. Cheap — `checkPause` returns at once unless a
            // drive is actually paused.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    pipeline.checkPause()
                }
            }
            // On the root, so the question is asked once wherever the
            // driver is — the drive view is presented over the Route tab,
            // and an alert on each would be two alerts.
            .alert(PauseText.title, isPresented: Binding(
                get: { pipeline.pauseNeedsAnswer },
                set: { if !$0 { pipeline.dismissPauseQuestion() } }
            )) {
                Button(PauseText.stillHere) { pipeline.keepPaused() }
                Button(PauseText.endDrive, role: .destructive) { pipeline.stopManualRecording() }
            } message: {
                Text(PauseText.body(limitMinutes: mapSettings.pauseLimitMinutes))
            }
        }
    }
}

#Preview {
    ContentView()
}
