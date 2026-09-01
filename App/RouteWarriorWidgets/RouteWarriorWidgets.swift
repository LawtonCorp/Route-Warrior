import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RouteWarriorWidgetBundle: WidgetBundle {
    var body: some Widget {
        GhostRaceLiveActivity()
        PlaceholderWidget()
    }
}

// MARK: - Ghost race Live Activity (FR-15, D-003)

// Google Maps owns the foreground while navigating, so the lock screen and
// Dynamic Island are the glanceable surfaces. One number dominates: ahead
// or behind. No interaction is expected while driving.
struct GhostRaceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GhostRaceAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "flag.checkered")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    deltaText(context.state.aheadSeconds)
                        .font(.title2.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                        Text("\(context.attributes.destinationName) · vs \(context.state.referenceLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
            } compactTrailing: {
                deltaText(context.state.aheadSeconds)
                    .font(.caption.monospacedDigit().bold())
            } minimal: {
                Image(systemName: context.state.aheadSeconds >= 0 ? "hare.fill" : "tortoise.fill")
            }
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<GhostRaceAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flag.checkered")
                Text("To \(context.attributes.destinationName)")
                    .font(.subheadline)
                Spacer()
                deltaText(context.state.aheadSeconds)
                    .font(.title.monospacedDigit().bold())
            }
            ProgressView(value: context.state.progress)
            Text(context.state.aheadSeconds >= 0
                 ? "Ahead of your \(context.state.referenceLabel)"
                 : "Behind your \(context.state.referenceLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .foregroundStyle(.white)
    }

    private func deltaText(_ aheadSeconds: Double) -> some View {
        let total = Int(abs(aheadSeconds).rounded())
        let text = String(format: "%@%d:%02d", aheadSeconds >= 0 ? "+" : "−", total / 60, total % 60)
        return Text(text)
            .foregroundStyle(aheadSeconds >= 0 ? Color.green : Color.orange)
    }
}

// MARK: - Home-screen placeholder widget

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "RouteWarriorPlaceholder",
            provider: PlaceholderProvider()
        ) { _ in
            Text("Route Warrior")
        }
        .configurationDisplayName("Route Warrior")
        .description("The ghost race appears live during repeat drives.")
    }
}

struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}
