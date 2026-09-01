import RouteWarriorStore
import SwiftData
import SwiftUI

@main
struct RouteWarriorApp: App {
    private let container: ModelContainer
    @State private var pipeline: RecordingPipeline
    @State private var locationService: LocationService

    init() {
        // CloudKit when available; local-only when iCloud is unavailable
        // (NFR-5 — nothing blocks, sync resumes when the account does);
        // in-memory only as the never-lose-the-launch last resort.
        let container = (try? RouteWarriorStoreFactory.cloudContainer())
            ?? (try? RouteWarriorStoreFactory.localContainer())
            ?? (try! RouteWarriorStoreFactory.inMemoryContainer())
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
                    locationService.start()
                }
        }
    }
}
