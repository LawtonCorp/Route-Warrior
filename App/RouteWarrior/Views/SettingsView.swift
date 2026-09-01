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
                    LabeledContent("Plan", value: store.tier == .pro ? "Pro" : "Free")
                    if store.tier == .free {
                        Button("Unlock unlimited history and the ghost race") {
                            showPaywall = true
                        }
                    }
                    Button("Restore purchases") {
                        Task { await store.restore() }
                    }
                }
                Section {
                    LabeledContent("Location", value: locationLabel)
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
                    LabeledContent(
                        "Motion",
                        value: locationService.motionAvailable ? "Available" : "Unavailable"
                    )
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Always-on location and motion access power hands-free trip recording. Your drives stay on this device and in your private iCloud — no accounts, no servers of ours.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
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

    private var locationLabel: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not set"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
