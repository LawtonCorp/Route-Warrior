import CoreLocation
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(LocationService.self) private var locationService

    @Environment(StoreService.self) private var store
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Route Warrior Pro") {
                    LabeledContent {
                        Text(store.tier == .pro ? "Pro" : "Free")
                    } label: {
                        settingsLabel("Plan", symbol: "star.fill", color: Theme.pro)
                    }
                    if store.tier == .free {
                        Button("Unlock unlimited history and the ghost race") {
                            showPaywall = true
                        }
                        .tint(Theme.pro)
                    }
                    Button("Restore purchases") {
                        Task { await store.restore() }
                    }
                }
                Section {
                    LabeledContent {
                        Text(locationLabel)
                    } label: {
                        settingsLabel("Location", symbol: "location.fill", color: Theme.route)
                    }
                    if locationService.authorizationStatus == .notDetermined {
                        Button("Allow location while using the app") {
                            locationService.requestWhenInUseAuthorization()
                        }
                    }
                    if locationService.authorizationStatus == .authorizedWhenInUse {
                        Button("Upgrade to Always (hands-free recording)") {
                            locationService.requestAlwaysAuthorization()
                        }
                    }
                    if locationService.authorizationStatus == .denied {
                        Link("Open system settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                    LabeledContent {
                        Text(motionLabel)
                    } label: {
                        settingsLabel("Motion", symbol: "figure.walk.motion", color: Theme.win)
                    }
                    if locationService.motionAuthorization == .denied {
                        Link("Allow motion in system settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Always-on location and motion access power hands-free trip recording. Your drives stay on this device and in your private iCloud — no accounts, no servers of ours.")
                }

                Section {
                    NavigationLink {
                        RecorderLogView()
                    } label: {
                        settingsLabel("Recorder log", symbol: "list.bullet.rectangle.fill", color: Theme.google)
                    }
                } footer: {
                    Text("What the recorder did on each drive — when it armed, started, and why it ended. Check here if a drive went missing.")
                }

                Section("About") {
                    LabeledContent {
                        Text(appVersion)
                    } label: {
                        settingsLabel("Version", symbol: "info.circle.fill", color: .gray)
                    }
                    Text("Trip data never leaves your devices except the route requests sent to Google at departure.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private func settingsLabel(_ title: String, symbol: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            IconTile(symbol: symbol, color: color)
        }
    }

    private var locationLabel: String {
        LocationService.label(locationService.authorizationStatus)
    }

    private var motionLabel: String {
        guard locationService.motionAvailable else { return "Unavailable" }
        return LocationService.label(locationService.motionAuthorization)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
