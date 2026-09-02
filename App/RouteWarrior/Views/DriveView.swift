import CoreLocation
import MapKit
import RouteWarriorKit
import SwiftUI
import UIKit

/// FR-21/FR-22: the map that follows the car. The plan (Apple's, on this
/// Apple surface — D-022 §9.2) is the dashed line; your trail is blue and
/// turns green the moment you leave the plan; a reroute, if asked for,
/// is a second line. Nothing here changes the departure snapshot. Pro.
struct DriveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(MapSettings.self) private var mapSettings
    @Environment(GhostRaceCoordinator.self) private var ghostRace
    @Environment(StoreService.self) private var store

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var monitor: DriveMonitor?

    /// The plan drawn on this surface.
    private var plan: PlanSnapshot? {
        pipeline.plansForCurrentDrive.first { $0.provider == .appleMaps }
    }

    private var isOffPlan: Bool {
        if case .offPlan = monitor?.offPlan { return true }
        return false
    }

    private var rerouteAllowed: Bool { store.policy.rerouteAvailable(for: store.tier) }

    var body: some View {
        ZStack(alignment: .top) {
            map
            banner
        }
        .overlay(alignment: .bottom) { controls }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            syncMonitor()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: plan?.id) { syncMonitor() }
        .onChange(of: pipeline.liveTrack.count) {
            monitor?.ingest(track: pipeline.liveTrack, autoReroute: mapSettings.autoReroute && rerouteAllowed)
        }
        .onChange(of: pipeline.isRecording) {
            if !pipeline.isRecording { dismiss() }
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            if let plan {
                MapPolyline(coordinates: Self.clCoordinates(plan.polyline))
                    .stroke(Theme.google, style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
            }
            if let reroute = monitor?.reroute {
                MapPolyline(coordinates: Self.clCoordinates(reroute.polyline))
                    .stroke(Theme.pro, lineWidth: 4)
            }
            if pipeline.liveTrack.count >= 2 {
                MapPolyline(coordinates: pipeline.liveTrack.map {
                    CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                })
                .stroke(isOffPlan ? Theme.win : Theme.route, lineWidth: 5)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(showsTraffic: true))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea()
    }

    // MARK: Banner

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(headline)
                    .font(.headline)
                Spacer()
                if let status = ghostRace.status {
                    Text(Format.signedDelta(status.aheadSeconds))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(status.aheadSeconds >= 0 ? Theme.win : Theme.google)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reroute = monitor?.reroute {
                Label(
                    "New plan drawn: \(Format.duration(reroute.trafficDuration)) from here. The original stays the baseline.",
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                )
                .font(.caption)
                .foregroundStyle(Theme.pro)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var headline: String {
        guard let plan else { return "No plan for this drive" }
        if isOffPlan { return "Off the plan — your way" }
        return "On \(plan.provider.displayName)'s plan"
    }

    private var detail: String {
        var parts: [String] = []
        if let plan, let startedAt = pipeline.recordingStartedAt {
            let eta = startedAt.addingTimeInterval(plan.trafficDuration)
            parts.append("\(plan.provider.displayName)'s ETA \(eta.formatted(date: .omitted, time: .shortened))")
        }
        if let startedAt = pipeline.recordingStartedAt {
            parts.append("\(Format.duration(Date.now.timeIntervalSince(startedAt))) so far")
        }
        if let status = ghostRace.status {
            parts.append("vs. your \(ghostRace.reference == .personalBest ? "best" : "average")")
        } else if plan != nil {
            parts.append("ghost race joins once the route is recognised")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Label("Hide", systemImage: "chevron.down")
            }
            .buttonStyle(.bordered)
            if rerouteAllowed, plan != nil {
                Button {
                    guard let last = pipeline.liveTrack.last else { return }
                    Task { await monitor?.requestReroute(from: last.coordinate, at: last.timestamp) }
                } label: {
                    if monitor?.rerouting == true {
                        ProgressView()
                    } else {
                        Label("Reroute", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.pro)
                .disabled(monitor == nil || monitor?.rerouting == true)
            }
            Spacer()
            Button(role: .destructive) {
                pipeline.stopManualRecording()
                dismiss()
            } label: {
                Label("End drive", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.recording)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Wiring

    @MainActor
    private func syncMonitor() {
        guard let plan else {
            monitor = nil
            return
        }
        guard monitor?.plan.id != plan.id else { return }
        let destinationID = plan.destinationPlaceID
        guard let destination = plan.destination else {
            monitor = nil
            return
        }
        monitor = DriveMonitor(plan: plan) { position in
            await pipeline.computePlan(
                from: position, to: destination, destinationPlaceID: destinationID, provider: .appleMaps
            )
        }
        monitor?.ingest(track: pipeline.liveTrack, autoReroute: false)
    }

    private static func clCoordinates(_ polyline: Polyline) -> [CLLocationCoordinate2D] {
        polyline.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
