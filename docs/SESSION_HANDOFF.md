# Session handoff — state of Route Rebel as of 2026-09-04

_Audience: the next AI coding session (and future Brian). The human-only
checklist lives in `docs/HANDOFF.md`; this file is everything else — what
exists, why, and what the previous sessions learned the hard way. Read
`CLAUDE.md` first; it is binding. Product rationale is in
`docs/REQUIREMENTS.md`, `docs/SPEC.md`, `docs/SPEC_IN_APP_MAP.md`,
`docs/BUILD_PLAN.md`, and every behaviour choice is logged in
`DECISIONS.md` (D-001…D-043; continue from D-044)._

## Where things stand

**The app is called Route Rebel** (display name only, D-030). The repo,
modules, bundle id `com.lawtoncorp.routewarrior` and CloudKit container
`iCloud.com.lawtoncorp.routewarrior` keep the old name on purpose: a
bundle-id change would orphan the App Store record, the provisioning and
every user's CloudKit data. Do not rename them unless Brian asks.

**v1 (M0–M6) and v2's in-app map (M7 + M8) are merged, and Brian is
field-testing daily.** Forty PRs have landed; `main` is green at #40;
there are no open PRs, no unpushed work and no scheduled check-ins. Brian
builds to his phone with `./scripts/device-build.sh` from
`/Users/roar/Route-Warrior` (CLI directory: that path; the script is
`scripts/device-build.sh` inside it).

What the app does today: auto-records drives hands-free, or from a plan;
the **Plan tab** (was Home) has a big "Where to?" field the driver types
into, the map under it, saved places under the map; both providers'
plans are snapshotted at departure; Google's Routes API and Apple's
MKDirections are compared against what was driven; stop signs/signals
from OpenStreetMap; turns counted from the line itself, lefts apart
(D-043), on trips, routes and each plan; per-destination verdicts, patterns, and a
head-to-head race between the driver's own routes; a lock-screen ghost
race; a live scoreboard on the drive view; Apple Maps hand-off for
CarPlay guidance; private CloudKit sync; StoreKit 2 Pro gating of
analysis surfaces only.

## Layout (the 30-second map)

- `Sources/RouteWarriorKit/` — ALL logic, UI-framework-free (enforced by
  `scripts/kit-purity-gate.sh`; also no CoreLocation/SwiftData/MapKit/
  WidgetKit/ActivityKit). Geo/Polyline (E5), TripRecorder, StopDetector,
  RouteMatcher, DestinationPredictor, StatsEngine, VerdictEngine,
  GhostRace, LiveMatch, TierPolicy, RoutesProviding, Overpass, and from
  this session: `RouteRaceEngine` (head-to-head between the driver's
  routes), `DriveScoreboard` (ahead/behind the plan and the ghost),
  `ArrivalDetector` (150 m / 20 s dwell / ≤2.5 m/s), `Place.Kind`
  (twelve kinds + custom, with `Kind(stored:)` decoder).
- `Sources/RouteWarriorStore/` — SwiftData @Model records + mapping +
  `StoreFactory`. `VariantRecord.customName` for renamed routes.
- `App/RouteWarrior/Services/` — RecordingPipeline (arrival stop, plan
  failure logging), LocationService (persists the last fix to
  `LastMapCenter`), GoogleRoutesClient (sends `X-Ios-Bundle-Identifier`,
  logs Google's reason with keys redacted), DrivePlanner (destination +
  plans state machine), AddressSearch (`AddressCompleter`, chain-branch
  lookup), MapSettings (provider, autoReroute, navigateWithAppleMaps,
  stopOnArrival), AppleMapsHandoff.
- `App/RouteWarrior/Support/` — MapScene (one scene for both map
  surfaces), SuggestionDetail (pure autocomplete merge), TripOrganizer
  (sort/filter), ScoreboardText, LastMapCenter, DestinationAnalytics,
  Format, Theme.
- `App/RouteWarrior/Views/` — HomeView (the Plan tab), DriveView (turn-
  by-turn with the scoreboard banner), TripsView (Today/Earlier + sort +
  filter), TripDetailView, DestinationDetailView (routes map, head-to-
  head card), VariantDetailView (rename, coloured multi-route map),
  PlacesView, PlacePickerMap, MapSurfaceView (Apple), GoogleMapSurface,
  Settings/Onboarding/Paywall.
- `App/RouteWarriorTests/` — app-target wiring tests, one per boundary
  feature (CLAUDE.md requires this; 25 files now).
- `project.yml` — the only project truth. `CFBundleDisplayName: Route
  Rebel` on both targets. The Maps SDK for iOS is a Swift Package here.

## Decisions with teeth (details in DECISIONS.md)

- **D-022 rule**: a provider's plan is drawn only on that provider's map
  surface (`MapScene.drawablePlans(for:)`); the driver's own recorded
  routes draw on every surface. The departure snapshot is never replaced
  by a reroute; both providers are snapshotted at every departure.
- **D-026**: the Plan tab *is* the planning surface — no plan sheet.
  Trips owns all history (Today at top, sort + outcome filter).
- **D-032**: the Google key is restricted to iOS apps, so every Routes
  call carries the bundle id header. A 403 here means a key/API/quota
  restriction in Google Cloud, and the Recorder log now says which.
- **D-034**: CarPlay guidance is Apple Maps via hand-off (a Settings
  toggle). Apple's navigation entitlement is not attainable for us; the
  *driving-task* entitlement is requested per `docs/HANDOFF.md` and the
  CarPlay scoreboard scene waits on it. Do not add the entitlement to
  `project.yml` before Apple grants it: `-allowProvisioningUpdates`
  would fail the device build.
- **D-036/D-037**: maps open on the last known fix (`LastMapCenter`,
  saved by LocationService on the first fix and every ≥500 m), never on
  the country view; follow mode keeps the driver's own zoom.
- **D-038**: a planned drive ends itself at the kerb (on by default).
- **D-040**: a chain's bare autocomplete rows are looked up as places and
  replaced by the nearest five branches with address and distance.
- **D-041**: when the recording ends with a destination on the Plan tab,
  the plan clears. **D-042**: the Apple surface draws the plan solid
  (MapKit renders dashed `MapPolyline` as blocks at planning zooms).
- **D-043**: `TurnCounter` counts turns from a line's shape (20 m
  heading windows, 45° in / 20° out); nothing persisted, computed where
  shown. Tune `TurnCounter.Config` if field tests disagree.
- Privacy (D-006) still holds: no accounts, no LawtonCorp server; the
  privacy label is "Data Not Collected"; do not add network calls
  casually. Pro gates analysis only (D-008, D-015); D-017 forces Pro on
  Brian's personal build via `ROUTEWARRIOR_FORCE_PRO=1` in
  `scripts/signing.local`.

## How to work here (environment truths)

- **GitHub Actions is the only compiler** from the cloud session. Local
  gates: `./scripts/kit-purity-gate.sh`, brace/paren balance on every
  edited Swift file (a three-line Python count is enough), and an
  adversarial read of the diff. Everything else is proven by CI.
- Flow: branch `claude/<topic>` from fresh `origin/main` → draft PR →
  when CI is green, mark ready and **squash-merge yourself** (Brian's
  standing "merge when green") → sync local main. Never merge red, never
  push to main. Use the GitHub MCP tools: `actions_list`
  (`list_workflow_runs`, `ci.yml`, branch filter, event `pull_request`),
  `get_job_logs` (`failed_only`, tail) for failures, `update_pull_request`
  (`draft: false`), `merge_pull_request` (squash, `expectedHeadSha`).
  Use `send_later` (≈9 min) as the wake timer for a CI check; never poll.
- CI takes 5–7 minutes per run. Two in-flight PRs that both touch
  `DECISIONS.md` will conflict; resolve by keeping both entries in
  numeric order.
- Commit footer and PR footer formats are given by the session harness;
  never put a model identifier in a commit, PR or code comment.
- Secrets: the Google key lives only in gitignored `scripts/signing.local`
  / environment and is injected by `device-build.sh` into Info.plist.
  Never paste it into chat; redact anything key-shaped in logs (the
  client already does, «key»).

## Scar tissue (bugs the next session should not re-earn)

- **Statics on a SwiftUI `View` are MainActor-isolated.** Anything read
  from a `nonisolated` helper or a test must be `nonisolated static`.
  This bit three PRs this session (`GoogleMapSurface.drivingZoom`,
  width constants, `dashMeters`). Same for `@MainActor` classes
  (`DrivePlanner.planEnds` is `nonisolated static` for this reason).
- Do not shadow with `let race = race` inside a closure; write
  `let race = self.race` or rename. Enumerated tuple destructuring with an
  explicit closure return type fails to type-check; use a `for` loop.
  Avoid `count(where:)` (stdlib availability) and regex literals.
- `PlaceTests` uses swift-testing (`@Test`/`#expect`); every other test
  file is XCTest. Match the file you are appending to.
- A struct with a custom `init` loses its memberwise init
  (`GhostRace.ReferenceProfile` needed `public init(samples:)`).
- Never replace a file region by slicing from an index — a
  `s[s.index("extension …"):]` edit deleted `IconTile` and `tintedRow`
  from `Theme.swift`. Bounded exact-match replacements only.
- Google's plan "not appearing" had three stacked causes: 12 m dashes
  (sub-pixel), a silent 403 (iOS-restricted key without the bundle-id
  header), and a thin dashed line lost under traffic colouring (needed a
  casing). If a route is invisible again, check the Recorder log first.
- The country-view-at-launch bug needed three rounds (D-027, D-036,
  D-037): the fix that held was persisting the centre *at the source*
  (LocationService), not when a map happened to frame itself.
- Earlier scars still apply: `Self` in stored-property initializers,
  CloudKit `ModelContainer` in unsigned CI builds (in-memory under a test
  host), SwiftData+CloudKit model rules, `-allowProvisioningUpdates` not
  registering App Groups/iCloud containers (Xcode → Signing → Try Again),
  never `killall CoreSimulatorService`, never sign in `project.yml`.

## What Brian has been asked to do (outside the repo)

1. **Google Cloud**: the key's API restriction list should include Routes
   API, Maps SDK for iOS, Places API (New), Geocoding, Roads, Directions,
   Distance Matrix, Time Zone, Elevation, Address Validation, Geolocation
   (the "sky is the limit" list he asked for). He has already raised the
   Routes API quotas; a daily cap of ~500 was advised.
2. **CarPlay driving-task entitlement**: request per `docs/HANDOFF.md`
   (choose *Driving task*, not Navigation). When granted, one PR adds the
   entitlement, the scene manifest and a
   `CPTemplateApplicationSceneDelegate` rendering `ScoreboardText.rows`.
3. App Privacy questionnaire, App Store checklist (`docs/HANDOFF.md` §5).

## What's next (likely session work)

1. Phone-in-hand confirmation of #39 and #40: chain searches ("Extra")
   expand into addressed branches; the Plan tab clears when a drive ends;
   Apple's plan draws as a line, not blocks.
2. Field-test findings arrive as screenshots with one-line reports; the
   pattern is diagnose → small PR → merge on green → "pull and rebuild".
3. Possible follow-ups mentioned, not requested: pausing follow-on-pan
   with a "resume" control on the Google drive view (needs the map
   delegate); a full internal rename only if Brian asks.
4. Nothing is red, pending or half-merged.

## Working with Brian

Substance over ceremony. He delegates thresholds and technical choices
("merge when green") but decides product questions; ask with concrete
options (AskUserQuestion worked well for the CarPlay direction). For
anything on his Mac, give exact commands or click steps — he pastes
terminal output back verbatim. He reads DECISIONS.md — keep writing the
"rejected" half of every entry. Reports come as screenshots; read them
closely, they often show a second defect he did not mention (the block
dashes in #40).
