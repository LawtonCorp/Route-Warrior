import SwiftUI

/// The root (D-053): onboarding, then the Terms-changed screen once per
/// new Terms version, then the app.
struct ContentView: View {
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
                    .tabItem { Label("Plan", systemImage: "car.fill") }
                TripsView()
                    .tabItem { Label("Trips", systemImage: "map") }
                PlacesView()
                    .tabItem { Label("Places", systemImage: "mappin.and.ellipse") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}

#Preview {
    ContentView()
}
