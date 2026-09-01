import SwiftUI
import WidgetKit

// The ghost-race Live Activity lands here at milestone M4. This placeholder
// exists from M0 so the extension target, its App Group, and its iCloud
// entitlements are wired (and CI-built) from the first commit — capabilities
// added later through Xcode's UI would not survive project regeneration.
@main
struct RouteWarriorWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "RouteWarriorPlaceholder",
            provider: PlaceholderProvider()
        ) { _ in
            Text("Route Warrior")
        }
        .configurationDisplayName("Route Warrior")
        .description("The ghost race arrives in a later release.")
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
