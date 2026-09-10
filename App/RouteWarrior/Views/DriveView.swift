import RouteWarriorKit
import SwiftUI
import UIKit

/// FR-21/FR-22: the map that follows the car, on the surface the user
/// chose. That provider's plan is the dashed line; your trail is blue and
/// turns green the moment you leave the plan; a reroute, if asked for, is
/// a second line. Turn-by-turn (D-052) sits above the scoreboard and
/// follows the plan, then the reroute. Nothing here changes the departure
/// snapshot. Pro.
struct DriveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecordingPipeline.self) private var pipeline
    @Environment(MapSettings.self) private var mapSettings
    @Environment(GhostRaceCoordinator.self) private var ghostRace
    @Environment(StoreService.self) private var store

    @State private var monitor: DriveMonitor?
    @State private var guide: DriveGuide?
    @State private var voice: GuidanceVoice?

    private var surfaceProvider: PlanSnapshot.Provider { mapSettings.provider.snapshotProvider }

    /// The plan drawn on this surface and judged against.
    private var plan: PlanSnapshot? {
        pipeline.plansForCurrentDrive.first { $0.provider == surfaceProvider }
    }

    private var isOffPlan: Bool {
        if case .offPlan = monitor?.offPlan { return true }
        return false
    }

    private var rerouteAllowed: Bool { store.policy.rerouteAvailable(for: store.tier) }
    private var guidanceOn: Bool { mapSettings.guidance && store.policy.guidanceAvailable(for: store.tier) }

    /// Following a reroute rather than the departure plan.
    private var guideOnReroute: Bool {
        guard let guide, let plan else { return false }
        return guide.following.id != plan.id
    }

    /// The maneuver to show: while on the plan, or while following a
    /// reroute; not while off the plan with nothing new to follow.
    private var shownGuidance: GuidanceEngine.Guidance? {
        guard guidanceOn, let guide, guide.hasSteps, let guidance = guide.guidance,
              !isOffPlan || guideOnReroute
        else { return nil }
        return guidance
    }

    /// Where the drive stands against the plan, right now (D-035).
    private var board: DriveScoreboard {
        DriveScoreboard.board(
            elapsed: pipeline.recordingStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0,
            position: pipeline.liveTrack.last?.coordinate ?? Coordinate(latitude: 0, longitude: 0),
            plan: pipeline.liveTrack.isEmpty ? nil : plan,
            ghost: ghostRace.status,
            offPlan: isOffPlan
        )
    }

    private var scene: MapScene {
        MapScene(
            plans: pipeline.plansForCurrentDrive,
            reroute: monitor?.reroute,
            trail: pipeline.liveTrack.map(\.coordinate),
            offPlan: isOffPlan,
            camera: .followUser,
            // A fallback for the moment before the map SDK has its own fix.
            userLocation: pipeline.liveTrack.last?.coordinate
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapSurfaceView(scene: scene)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                if let shownGuidance {
                    GuidanceBanner(
                        guidance: shownGuidance,
                        distance: guide?.distanceText ?? "",
                        onReroute: guideOnReroute
                    )
                }
                banner
            }
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
            if let last = pipeline.liveTrack.last {
                guide?.ingest(position: last.coordinate)
            }
        }
        .onChange(of: monitor?.reroute?.id) {
            // A reroute is a second line (D-022): guidance follows it,
            // the scoreboard and the verdict keep the departure plan.
            if let reroute = monitor?.reroute {
                guide?.follow(reroute)
            }
        }
        .onChange(of: mapSettings.guidanceVoice) {
            guide?.voiceEnabled = mapSettings.guidanceVoice
        }
        .onChange(of: pipeline.isRecording) {
            if !pipeline.isRecording { dismiss() }
        }
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
            if let ahead = board.aheadOfPlanSeconds {
                Text(ScoreboardText.headline(board, provider: surfaceProvider.displayName))
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(ahead >= 0 ? Theme.win : Theme.google)
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
        .padding(.top, shownGuidance == nil ? 8 : 0)
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
        if ghostRace.status != nil {
            parts.append("vs. your \(ghostRace.reference == .personalBest ? "best" : "average")")
        } else if plan != nil {
            parts.append("ghost race joins once the route is recognised")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Hide the drive view")
            if rerouteAllowed, plan != nil {
                Button {
                    guard let last = pipeline.liveTrack.last else { return }
                    Task { await monitor?.requestReroute(from: last.coordinate, at: last.timestamp) }
                } label: {
                    if monitor?.rerouting == true {
                        ProgressView()
                            .frame(width: 22, height: 22)
                    } else {
                        Label("Reroute", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.pro)
                .disabled(monitor == nil || monitor?.rerouting == true)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                pipeline.stopManualRecording()
                dismiss()
            } label: {
                Label("End", systemImage: "stop.fill")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.recording)
            .accessibilityLabel("End the drive")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Wiring

    @MainActor
    private func syncMonitor() {
        guard let plan else {
            monitor = nil
            guide = nil
            return
        }
        guard monitor?.plan.id != plan.id else { return }
        let destinationID = plan.destinationPlaceID
        let provider = plan.provider
        guard let destination = plan.destination else {
            monitor = nil
            guide = nil
            return
        }
        monitor = DriveMonitor(plan: plan) { position in
            await pipeline.computePlan(
                from: position, to: destination, destinationPlaceID: destinationID, provider: provider
            )
        }
        monitor?.ingest(track: pipeline.liveTrack, autoReroute: false)
        let voice = self.voice ?? GuidanceVoice()
        self.voice = voice
        let guide = DriveGuide(plan: plan, units: DriveGuide.localUnits(), voice: voice)
        guide.voiceEnabled = mapSettings.guidanceVoice
        self.guide = guide
        if guidanceOn, guide.hasSteps {
            pipeline.note("Guidance follows \(plan.provider.displayName)'s plan: \(plan.steps.count) steps")
        }
        if let last = pipeline.liveTrack.last {
            guide.ingest(position: last.coordinate)
        }
    }
}

/// The maneuver ahead: arrow, distance, words, and the one after (D-052).
struct GuidanceBanner: View {
    let guidance: GuidanceEngine.Guidance
    let distance: String
    /// Following a reroute rather than the departure plan.
    var onReroute = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: ManeuverSymbol.name(for: guidance.maneuver))
                .font(.system(size: 34, weight: .bold))
                .frame(width: 44)
                .foregroundStyle(guidance.arrived ? Theme.win : Theme.route)
            VStack(alignment: .leading, spacing: 2) {
                if guidance.arrived {
                    Text("You have arrived")
                        .font(.title2.bold())
                } else {
                    Text(distance)
                        .font(.title2.monospacedDigit().bold())
                    Text(guidance.instruction)
                        .font(.headline)
                        .lineLimit(2)
                }
                if !guidance.arrived, let then = guidance.then {
                    Text("Then \(then.instruction)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if onReroute {
                    Text("Following the new plan")
                        .font(.caption)
                        .foregroundStyle(Theme.pro)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}
