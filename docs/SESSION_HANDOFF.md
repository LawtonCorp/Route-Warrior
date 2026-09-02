# Session handoff — state of Route Warrior as of 2026-09-02

_Audience: the next AI coding session (and future Brian). The human-only
checklist lives in `docs/HANDOFF.md`; this file is everything else — what
exists, why, and what the previous session learned the hard way. Read
`CLAUDE.md` first; it is binding. Product rationale is in
`docs/REQUIREMENTS.md`, `docs/SPEC.md`, `docs/BUILD_PLAN.md`, and every
behaviour choice is logged in `DECISIONS.md` (D-001…D-021; continue from
D-022)._

## Where things stand

**v1 is code-complete and on Brian's phone.** All milestones M0–M6 from
`docs/BUILD_PLAN.md` are implemented, tested, and merged; `main` is green.
Fourteen PRs landed (#1 planning docs, #2–#13 the build, #14 app icon +
Pro override). Brian built to his device ("Brown Chicken Brown Cow") with
`./scripts/device-build.sh` after a one-time provisioning fix, and has the
app icon and a forced-Pro personal build.

What v1 does: auto-records drives hands-free (CoreMotion arm →
CoreLocation record), snapshots Google's planned route + traffic-aware ETA
at departure via the Routes API, counts stop signs/signals from
OpenStreetMap, computes actual-vs-predicted verdicts and day×hour
patterns per destination, races a lock-screen ghost (Live Activity)
against the personal best on repeat routes, syncs via the user's private
CloudKit, and gates history depth / analyzed destinations / ghost race
behind a StoreKit 2 Pro subscription — recording itself is never gated.

## Layout (the 30-second map)

- `Sources/RouteWarriorKit/` — ALL logic, UI-framework-free (enforced by
  `scripts/kit-purity-gate.sh`; per D-009 also no CoreLocation/SwiftData/
  MapKit/WidgetKit/ActivityKit). Geo/Polyline (E5), TripRecorder (state
  machine), StopDetector, RouteMatcher, DestinationPredictor, StatsEngine,
  VerdictEngine, GhostRace, LiveMatch, TierPolicy, RoutesProviding
  (protocol + Google response parser), Overpass (+StopClassifier).
- `Sources/RouteWarriorStore/` — SwiftData @Model records + mapping +
  `StoreFactory` (CloudKit container `iCloud.com.lawtoncorp.routewarrior`).
- `App/RouteWarrior/` — thin SwiftUI layer. `Services/` wires kit to OS
  frameworks: RecordingPipeline, LocationService (power tiering),
  GoogleRoutesClient (key from Info.plist `GoogleRoutesAPIKey`),
  OverpassService, GhostRaceCoordinator, LiveActivityPresenter,
  StoreService (tier authority; D-017 override), DestinationPromptService
  (FR-6 notification fallback). `Views/` Home/Trips/TripDetail/Places/
  DestinationDetail/Settings/Onboarding/Paywall.
- `App/RouteWarriorWidgets/` — Live Activity; `App/Shared/` — the
  ActivityAttributes contract compiled into both targets.
- `App/RouteWarriorTests/` — app-target wiring tests (one per kit/app
  boundary feature; CLAUDE.md requires this).
- `project.yml` — the only source of project truth (XcodeGen); the
  `.xcodeproj` is generated and gitignored. Entitlements (App Group +
  iCloud container) are declared there for BOTH app and widget targets.

## Decisions with teeth (details in DECISIONS.md)

Google Routes API is the comparison source (D-001); snapshot once at
departure against the *predicted* destination — no retroactive ETA exists,
so a misprediction means "no comparison", with the FR-6 notification
one-tap fallback (D-010, D-016). Keyless builds degrade gracefully.
Privacy: no accounts, no LawtonCorp server, on-device + private CloudKit
only (D-006) — the privacy label is "Data Not Collected"; don't add
network calls casually. Free tier records everything forever; Pro gates
analysis surfaces only (D-008, D-015). D-017: `ROUTEWARRIOR_FORCE_PRO=1`
in `scripts/signing.local` forces Pro on personal device builds via an
Info.plist value injected by `device-build.sh`; empty everywhere else, an
app-target test proves unforced builds start free.

## How to work here (environment truths)

- **GitHub Actions is the only compiler** from the cloud session. Gates
  runnable locally: `./scripts/kit-purity-gate.sh`, YAML/JSON validation,
  brace-balance, `bash -n`, and an adversarial diff read. Everything else
  is proven by CI.
- Flow: branch `claude/<topic>` from fresh `origin/main` → PR → **squash-
  merge yourself when CI is green** (Brian's standing "merge when ready");
  never merge red, never push to main. Subscribe to PR events
  (`subscribe_pr_activity`) and use a background `sleep` as a wake timer;
  never poll in a loop.
- Reading CI failures: fetch job *logs* through the GitHub MCP tool
  (`get_job_logs`, tail) — the raw-log URL redirects to a blob host the
  proxy blocks. `ci.yml`'s last step greps the real errors to the tail.
  Check-run status lags; a 404 from get_job_logs means "still running".
- Run at most ~2 PRs' CI in parallel — the macOS runners saturate.

## Scar tissue (bugs the next session should not re-earn)

- **Swift 6 strict concurrency**: `Self` is illegal in stored-property
  initializers (name the type); statics on a `@MainActor` class are
  isolated (`nonisolated static let` where needed); a nonisolated deinit
  cannot touch isolated state; keep non-Sendable ObjC objects
  (UNUserNotificationCenter) inside one `Task.detached` region and call
  completion handlers before hopping actors; don't read a `self` property
  inside a closure passed to a mutating call on `self` (hoist to a local).
- **CloudKit + tests**: creating a CloudKit `ModelContainer` without the
  entitlement (unsigned CI builds!) raises an uncatchable ObjC exception —
  `try?` will not save you; the app detects a test host
  (`NSClassFromString("XCTestCase")`) and uses in-memory storage. A
  SIGTRAP "before starting test execution" in CI is this class of bug.
- **SwiftData + CloudKit**: every `@Model` property defaulted or optional,
  no `#Unique`; kit types cross as Codable JSON blobs / E5 polylines.
- **Provisioning**: `-allowProvisioningUpdates` registers bundle IDs but
  not App Groups/iCloud containers; the one-time fix is Xcode →
  target → Signing & Capabilities → "Try Again" (portal registration
  persists; GUI-set signing is disposable — never commit it).
- Never `killall CoreSimulatorService`; never put signing in
  `project.yml`; regeneration discards anything Xcode's UI wrote.
- Verification: fixtures must be external (Google's documented polyline
  example, Movable Type haversine, equator geometry) — a fixture generated
  by the code under test proves nothing. Say plainly which claims are
  machine-checked and which need a phone in hand.

## What's next

1. **Brian's checklist** (`docs/HANDOFF.md`, in order): Google Routes API
   key → field tests (M2 recording week, M3 comparison sanity, M4 ghost
   race, CloudKit two-device sync) → App Store Connect subscription
   products → privacy-policy hosting, demo video, screenshots, TestFlight,
   submission.
2. **Likely follow-up work for a session**: tuning `TripRecorder.Config`
   thresholds when field tests disagree with reality (record the change in
   DECISIONS.md); OSM count corrections; any App Review feedback.
3. Nothing is currently red, pending, or half-merged. There are no open
   PRs and no unpushed work.

## Working with Brian

Substance over ceremony — a plan that is "a plan to create a plan" gets
rejected. He delegates thresholds and technical choices ("merge when
ready") but decides product questions; ask with concrete options. For
anything on his Mac, give exact screen-click instructions. He reads
DECISIONS.md — keep writing the "rejected" half of every entry.
