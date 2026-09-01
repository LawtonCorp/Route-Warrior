import RouteWarriorStore
import SwiftData
import SwiftUI

@main
struct RouteWarriorApp: App {
    private let container: ModelContainer
    @State private var pipeline: RecordingPipeline
    @State private var locationService: LocationService

    /// True when this process is the unit-test host. The host must not
    /// bootstrap CloudKit (the unsigned test build has no iCloud
    /// entitlement, and CoreData answers with an uncatchable ObjC
    /// exception, not a Swift throw) or start location services — tests
    /// build their own in-memory stores and pipelines.
    private static var isTestHost: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    init() {
        // CloudKit when available; local-only when iCloud is unavailable
        // (NFR-5 — nothing blocks, sync resumes when the account does);
        // in-memory for the test host and as the never-lose-the-launch
        // last resort.
        let container: ModelContainer
        if Self.isTestHost {
            container = try! RouteWarriorStoreFactory.inMemoryContainer()
        } else {
            container = (try? RouteWarriorStoreFactory.cloudContainer())
                ?? (try? RouteWarriorStoreFactory.localContainer())
                ?? (try! RouteWarriorStoreFactory.inMemoryContainer())
        }
        self.container = container
        let pipeline = RecordingPipeline(context: ModelContext(container))
        _pipeline = State(initialValue: pipeline)
        _locationService = State(initialValue: LocationService(pipeline: pipeline))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pipeline)
                .environment(locationService)
                .modelContainer(container)
                .task {
                    if !Self.isTestHost {
                        locationService.start()
                    }
                }
        }
    }
}
