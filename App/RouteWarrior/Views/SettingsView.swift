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
                    Toggle(isOn: Binding(
                        get: { mapSettings.guidance },
                        set: { mapSettings.setGuidance($0) }
                    )) {
                        settingsLabel("Turn-by-turn on the drive view", symbol: "arrow.turn.up.right", color: Theme.route)
                    }
                    .disabled(!store.policy.guidanceAvailable(for: store.tier))
                    Toggle(isOn: Binding(
                        get: { mapSettings.guidanceVoice },
                        set: { mapSettings.setGuidanceVoice($0) }
                    )) {
                        settingsLabel("Spoken directions", symbol: "speaker.wave.2.fill", color: Theme.route)
                    }
                    .disabled(!store.policy.guidanceAvailable(for: store.tier) || !mapSettings.guidance)
                } header: {
                    Text(SettingsText.inAppHeader)
                } footer: {
                    Text(SettingsText.inAppFooter(
                        providerCount: mapSettings.availableProviders.count,
                        rerouteAvailable: store.policy.rerouteAvailable(for: store.tier),
                        guidanceAvailable: store.policy.guidanceAvailable(for: store.tier)
                    ))
                }

                // Its own section since D-068: the header is what tells
                // this "Google" from the one three rows above it.
                Section {
                    Picker(selection: Binding(
                        get: { mapSettings.navigation },
                        set: { mapSettings.setNavigation($0) }
                    )) {
                        ForEach(mapSettings.availableHandoffs, id: \.self) { handoff in
                            Text(handoff.label).tag(handoff)
                        }
                    } label: {
                        settingsLabel("Navigate with", symbol: "arrow.triangle.turn.up.right.circle.fill", color: Theme.win)
                    }
                } header: {
                    Text(SettingsText.goHeader)
                } footer: {
                    Text(SettingsText.goFooter(
                        navigation: mapSettings.navigation,
                        googleMapsOffered: mapSettings.availableHandoffs.contains(.googleMaps)
                    ))
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { mapSettings.stopOnArrival },
                        set: { mapSettings.setStopOnArrival($0) }
                    )) {
                        settingsLabel("Stop on arrival", symbol: "flag.checkered", color: Theme.win)
                    }
                    Picker(selection: Binding(
                        get: { mapSettings.pauseLimitMinutes },
                        set: { mapSettings.setPauseLimit(minutes: $0) }
                    )) {
                        ForEach(MapSettings.pauseLimitChoices, id: \.self) { minutes in
                            Text(PauseText.limitValue(minutes)).tag(minutes)
                        }
                    } label: {
                        settingsLabel("Pause becomes a stop after", symbol: "pause.circle.fill", color: Theme.armed)
                    }
                } header: {
                    Text("Recording")
                } footer: {
                    Text("A planned drive ends itself once you have been within about 150 metres of the destination, moving at walking pace or slower, for 20 seconds. Driving past on the way somewhere else does not count. Drives without a plan still end on their own when the car stops. "
                        + PauseText.settingsFooter(limitMinutes: mapSettings.pauseLimitMinutes))
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
                    ForEach(Legal.Document.allCases, id: \.title) { document in
                        NavigationLink {
                            LegalDocumentView(document: document)
                        } label: {
                            settingsLabel(document.title, symbol: document.symbol, color: .gray)
                        }
                    }
                    Text("Trip data never leaves your devices except the route requests sent to the mapping providers at departure.")
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
