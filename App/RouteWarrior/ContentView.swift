import SwiftUI

struct ContentView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        if onboardingComplete {
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "car.fill") }
                TripsView()
                    .tabItem { Label("Trips", systemImage: "map") }
                PlacesView()
                    .tabItem { Label("Places", systemImage: "mappin.and.ellipse") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
}
