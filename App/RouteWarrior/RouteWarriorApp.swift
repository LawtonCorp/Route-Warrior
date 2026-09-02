import GoogleMaps
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI

@main
struct RouteWarriorApp: App {
    private let container: ModelContainer
    @State private var pipeline: RecordingPipeline
    @State private var locationService: LocationService
    @State private var store: StoreService
    @State private var destinationPrompt: DestinationPromptService
    @State private var mapSettings: MapSettings
    @State private var ghostRace: GhostRaceCoordinator

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
        // Apple's plan is always available (free, keyless); Google's rides
        // along whenever a key is present so every trip feeds both verdicts
        // ("beat both", D-022). Keyless builds simply have one provider.
        let key = GoogleRoutesClient.configuredKey
        var providers: [PlanSnapshot.Provider: any RoutesProviding] = [.appleMaps: AppleDirectionsClient()]
        if !key.isEmpty {
            providers[.googleRoutes] = GoogleRoutesClient(apiKey: key)
        }
        // The Google map surface needs the SDK primed with the key before
        // any GMSMapView exists (M8). Keyless and test-host builds skip it.
        if !key.isEmpty, !Self.isTestHost {
            GMSServices.provideAPIKey(key)
        }
        let mapSettings = MapSettings(googleAvailable: MapSettings.googleAvailable(hasKey: !key.isEmpty))
        _mapSettings = State(initialValue: mapSettings)
        let pipeline = RecordingPipeline(
            context: ModelContext(container),
            providers: providers,
            preference: { mapSettings.provider },
            logStorage: Self.isTestHost ? nil : UserDefaults.standard
        )
        _pipeline = State(initialValue: pipeline)
        let store = StoreService()
        _store = State(initialValue: store)
        let ghostRace = GhostRaceCoordinator(
            context: ModelContext(container),
            presenter: Self.isTestHost ? nil : LiveActivityPresenter(),
            tierProvider: { store.tier }
        )
        _ghostRace = State(initialValue: ghostRace)
        _locationService = State(initialValue: LocationService(
            pipeline: pipeline,
            ghostRace: ghostRace
        ))
        let prompt = DestinationPromptService(onPick: { placeID in
            pipeline.requestSnapshot(to: placeID)
        })
        _destinationPrompt = State(initialValue: prompt)
        if !Self.isTestHost {
            pipeline.onDestinationUnknown = { places in
                prompt.prompt(with: places)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pipeline)
                .environment(locationService)
                .environment(store)
                .environment(mapSettings)
                .environment(ghostRace)
                .modelContainer(container)
                .task {
                    if !Self.isTestHost {
                        locationService.start()
                        store.start()
                    }
                }
        }
    }
}
