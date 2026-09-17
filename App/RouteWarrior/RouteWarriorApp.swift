import GoogleMaps
import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import SwiftUI
import UIKit

@main
struct RouteWarriorApp: App {
    /// The launch hook auto-recording depends on (D-078). A background
    /// relaunch builds no window, so the root view's `.task` is not one.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var pipeline: RecordingPipeline
    @State private var locationService: LocationService
    @State private var store: StoreService
    @State private var prompts: PromptService
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
        let mapSettings = MapSettings(
            googleAvailable: MapSettings.googleAvailable(hasKey: !key.isEmpty),
            googleMapsInstalled: GoogleMapsHandoff.isAppInstalled
        )
        _mapSettings = State(initialValue: mapSettings)
        let store = StoreService()
        _store = State(initialValue: store)
        let pipeline = RecordingPipeline(
            context: ModelContext(container),
            providers: providers,
            preference: { mapSettings.provider },
            arrivalStop: { mapSettings.stopOnArrival },
            pauseWatch: { mapSettings.pauseWatch },
            tier: { store.tier },
            policy: store.policy,
            logStorage: Self.isTestHost ? nil : UserDefaults.standard
        )
        _pipeline = State(initialValue: pipeline)
        let ghostRace = GhostRaceCoordinator(
            context: ModelContext(container),
            presenter: Self.isTestHost ? nil : LiveActivityPresenter(),
            tierProvider: { store.tier }
        )
        _ghostRace = State(initialValue: ghostRace)
        let locationService = LocationService(pipeline: pipeline, ghostRace: ghostRace)
        _locationService = State(initialValue: locationService)
        let prompts = PromptService(
            onPick: { placeID in pipeline.requestSnapshot(to: placeID) },
            onStillHere: { pipeline.keepPaused() },
            onEndDrive: { pipeline.stopManualRecording() }
        )
        _prompts = State(initialValue: prompts)
        if !Self.isTestHost {
            pipeline.onDestinationUnknown = { places in
                prompts.promptDestination(with: places)
            }
            pipeline.onPauseStillThere = { limitMinutes in
                // On screen, the alert asks (D-072). A notification as
                // well would ask the same question twice.
                guard UIApplication.shared.applicationState != .active else { return }
                prompts.promptStillThere(limitMinutes: limitMinutes)
            }
            pipeline.onPauseAnswered = { prompts.clearStillThere() }
            // Start listening from the launch itself, however the launch
            // came about (D-078) — this is the only path a background
            // relaunch takes. Order-independent: the delegate may report
            // the launch before or after this runs.
            LaunchCoordinator.shared.onLaunch { reason in
                locationService.start(reason: reason)
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
                        // `start()` is idempotent; on a foreground launch
                        // the launch hook has already run it (D-078).
                        locationService.start()
                        store.start()
                    }
                }
        }
    }
}
