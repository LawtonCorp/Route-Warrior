import SwiftUI

struct ContentView: View {
    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
