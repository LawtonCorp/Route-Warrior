import CoreLocation
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(LocationService.self) private var locationService

    @Environment(StoreService.self) private var store
    @Environment(MapSettings.self) private var mapSettings
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Route Rebel Pro") {
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
                    Picker(selection: Binding(
                        get: { mapSettings.provider },
                        set: { mapSettings.select($0) }
                    )) {
                        ForEach(mapSettings.availableProviders, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    } label: {
                        settingsLabel("Map & routes", symbol: "map.fill", color: Theme.route)
                    }
                    Toggle(isOn: Binding(
                        get: { mapSettings.autoReroute },
                        set: { mapSettings.setAutoReroute($0) }
                    )) {
                        settingsLabel("Reroute automatically", symbol: "arrow.triangle.turn.up.right.diamond.fill", color: Theme.google)
                    }
                    .disabled(!store.policy.rerouteAvailable(for: store.tier))
                } header: {
                    Text("Map")
                } footer: {
                    Text(mapFooter)
                }

                Section {
                    LabeledContent {
                        Text(locationLabel)
                    } label: {
                        settingsLabel("Location", symbol: "location.fill", color: Theme.route)
                    }
                    if let warning = LocationPrimer.warning(for: locationService.authorizationStatus) {
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LocationFixButton()
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

    private var mapFooter: String {
        var lines: [String] = []
        if mapSettings.availableProviders.count == 1 {
            lines.append("Apple's map and routes. The Google map arrives in a later update; Google's plan is still compared on every trip when a key is present.")
        } else {
            lines.append("Whose map and routes you see. Both providers' plans are compared on every trip.")
        }
        lines.append(store.policy.rerouteAvailable(for: store.tier)
            ? "Automatic reroute asks for a fresh plan when you leave the one you started with. The original plan stays the baseline for the verdict."
            : "Automatic reroute is part of Pro.")
        return lines.joined(separator: " ")
    }

    private var motionLabel: String {
        guard locationService.motionAvailable else { return "Unavailable" }
        return LocationService.label(locationService.motionAuthorization)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
