# Decisions

Every behaviour change gets an entry: what was chosen, what was rejected,
and why.

## D-001 — Comparison source: Google Routes API (2026-09-01)

**Chosen**: snapshot Google's plan (polyline, static + traffic-aware ETA,
alternates) via the Routes API at departure. **Rejected**: Apple MapKit
directions (free, key-less, more private — but the product question is
literally "am I faster than *Google*?"); both providers (extra complexity
without a v1 payoff). iOS offers no access to another app's navigation
session, so the app must ask a routing service itself.

## D-002 — Recording: auto-detect with manual backup (2026-09-01)

**Chosen**: auto-detect driving via motion + location, with a manual
record/stop as backup and correction. **Rejected**: manual-only (forgotten
trips poison the averages); geofence-only auto-start (misses trips that
don't begin at a saved place).

## D-003 — In-drive UX: Live Activity ghost race (2026-09-01)

**Chosen**: live ahead/behind vs. personal best/average, rendered as a Live
Activity (lock screen + Dynamic Island), because Google Maps owns the
foreground during navigation. **Rejected**: record-silently v1 (Brian wants
the live race); turn-by-turn navigation in-app (that's building a nav app —
out of scope, see REQUIREMENTS non-goals).

## D-004 — Audience: public App Store product (2026-09-01)

**Chosen**: built for strangers from day one — onboarding, per-user API
cost strategy, support surface. **Rejected**: personal tool with a public
listing (would bake in single-user shortcuts, especially around the Google
API key).

## D-005 — Stops/signals: hybrid counting (2026-09-01)

**Chosen**: OpenStreetMap intersection data along the route corridor
(signals well-mapped, stop signs patchier) combined with motion-detected
stop events, reported side by side with a coverage-confidence label.
**Rejected**: motion-only (a signal crossed on green is invisible);
map-data-only (accuracy hostage to local OSM coverage). There is no
authoritative stop-sign feed; honesty about accuracy is part of the spec.

## D-006 — Privacy: private by default, sharing-ready schema (2026-09-01)

**Chosen**: no accounts, no LawtonCorp server, no third-party
analytics/ads; data only on-device + the user's private CloudKit database;
schema uses stable UUIDs and self-contained records so opt-in sharing could
arrive later without migrations. **Rejected**: sharing features in v1;
designs that would require a backend of ours.

## D-007 — Persistence: SwiftData + private CloudKit (2026-09-01)

**Chosen**: SwiftData models (in a dedicated `RouteWarriorStore` package
target) mirrored to the user's private CloudKit database — sync across the
user's devices with no server to run. **Rejected**: local-only (Brian chose
cross-device sync); Core Data (SwiftData is the iOS 17-era default and the
repo starts greenfield); custom backend (conflicts with D-006).

## D-008 — Monetization: free + Pro subscription (2026-09-01)

**Chosen**: free tier (unlimited recording, 30-day history, 2 analyzed
destinations) + Pro subscription (unlimited history/destinations, ghost
race, full analytics) via StoreKit 2, enforced on-device. Recording is
never gated so data accrues and upgrading is instantly valuable.
**Rejected**: one-time paid (ongoing Google API costs against a one-time
price); free-and-monetize-later (unbounded API cost exposure).

## D-009 — Kit boundaries: no CoreLocation or SwiftData in the kit (2026-09-01)

**Chosen**: `RouteWarriorKit` defines its own value types (Coordinate,
TrackPoint, …); the app converts `CLLocation` at the boundary; SwiftData
lives in a separate `RouteWarriorStore` target. **Rejected**: CoreLocation
types inside the kit (ties algorithms to Apple types and muddies the purity
story); SwiftData models inside the kit target (persistence concerns leak
into every algorithm test).

## D-010 — Destination prediction at departure (2026-09-01)

**Chosen**: predict the destination at trip start from history (origin,
weekday, time slot, initial bearing) to make the Google snapshot possible;
below-confidence trips record without a comparison and offer a one-tap
manual pick. **Rejected**: retroactive ETA lookup after arrival (Google
offers no "ETA as of a past departure" — the snapshot must happen in real
time); always asking the user at departure (friction kills the zero-touch
recording promise).

## D-011 — M0 scaffolding choices (2026-09-01)

**Chosen**: rename per the template checklist; App Group
`group.com.lawtoncorp.routewarrior` and container
`iCloud.com.lawtoncorp.routewarrior` declared in `project.yml` for both the
app and widget targets from M0, with a placeholder widget so the extension
is CI-built from the first commit; `RouteWarriorStore` package target
stubbed; signing variables renamed (`STARTER_TEAM` → `ROUTEWARRIOR_TEAM`,
`STARTER_DEVICE` → `ROUTEWARRIOR_DEVICE`); purity gate extended to also
forbid CoreLocation/SwiftData/MapKit/WidgetKit/ActivityKit in the kit and
UI frameworks in the Store. **Rejected**: deferring the widget target and
entitlements to M4 — capabilities added later through Xcode's UI die on
regeneration, and wiring them now proves them in CI while the surface is
tiny.

## D-012 — M2 app-layer choices (2026-09-01)

**Chosen**: a `RecordingPipeline` object as the single kit/app boundary
(samples in, persisted records out) so wiring is testable without
CoreLocation; power tiering in `LocationService` (significant-change +
motion while idle, full-rate GPS only while armed/recording, background
updates only with Always authorization); container fallback chain
CloudKit → local-only → in-memory so launch never blocks on iCloud
(NFR-5); trips that fail to persist surface the error in the UI rather
than dying silently; the template's Greeting placeholder replaced by real
wiring tests. **Rejected**: continuous GPS while idle (battery, NFR-3);
crashing on persistence failure; a combined location+persistence object
(untestable without a device).

## D-013 — M3 comparison wiring (2026-09-01)

**Chosen**: snapshots fetched in a background task at trip start (predict
destination from history, fetch top one or two per FR-6), held pending,
and attached at finalize only when the predicted destination matches
where the drive actually ended — mispredicted snapshots are dropped, not
misattached. The Google API key rides an Info.plist entry populated from
the `ROUTEWARRIOR_ROUTES_KEY` build setting (device-build.sh injects it
from the environment or signing.local; CI stays keyless, so CI builds
exercise the no-comparison path). Overpass inventories fetch on demand
when a destination's analytics appear, once per variant, with silent
retry on the next appearance. **Rejected**: blocking trip finalization on
the snapshot fetch (recording must never wait on a network); attaching
the nearest-in-time snapshot regardless of destination (silent
misattribution is worse than no comparison); committing any key material
to the repository.

## D-014 — M4 ghost race wiring (2026-09-01)

**Chosen**: the race rides the recording lifecycle from LocationService
(begin on first recorded sample, feed the live track, end with the
trip); variant recognition through the kit's one-way `liveMatch` with an
800 m commitment floor; personal best as the default reference (bucket
average selectable); Live Activity updates throttled to ~15 s, driven by
sample timestamps so behavior is deterministic and testable; the
presenter is a seam (`GhostRacePresenting`) so tests use a spy and only
the production presenter touches ActivityKit; until M5's StoreService
lands, the coordinator's tier provider defaults to Pro. **Rejected**:
symmetric-deviation matching for partial tracks (the undriven remainder
dominates — see the kit test proving it); per-sample Live Activity
updates (ActivityKit throttling and battery); in-app race UI as primary
surface (Google Maps owns the foreground, D-003).

## D-015 — M5 monetization and onboarding wiring (2026-09-01)

**Chosen**: StoreKit 2 subscription state in one `StoreService`
(entitlement refresh on launch and on every transaction update), with the
kit's TierPolicy deciding what a tier may do; free-tier history gated in
the UI through a testable `HistoryGate` (old trips hidden, never
deleted); analyzed-destination gating by list rank with a lock row that
opens the paywall; the ghost race's tier provider now reads the real
entitlement; onboarding as a conditional root view (value → privacy →
permission primers, per FR-18) tracked by one AppStorage flag; a
`.storekit` configuration file so purchase flows test in the simulator
without App Store Connect. Prices are placeholders ($2.99/$19.99) — the
real numbers are set in App Store Connect at handoff. **Rejected**:
server-side receipt validation (conflicts with the no-server privacy
stance; StoreKit 2's on-device verification is the accepted trade-off);
gating recording itself (D-008: data accrues so upgrading is instantly
valuable); a hard paywall at first launch.

## D-016 — M6 compliance and the FR-6 pick fallback (2026-09-01)

**Chosen**: FR-6's no-confidence fallback as a local notification with
the saved places as one-tap actions (`DestinationPromptService` +
`RecordingPipeline.requestSnapshot(to:)` — the pick fetches the plan
from wherever the drive currently is; ignoring it just means "no
comparison"); `PrivacyInfo.xcprivacy` declaring no tracking, no
collected data, and the three accessed-API categories the code actually
touches (UserDefaults, SystemBootTime for CoreMotion timestamp
conversion, FileTimestamp for SwiftData); the App Store artifacts
(privacy policy, review notes with the Always-location justification,
listing copy, handoff checklist) as repo docs so submission is
copy-paste. **Rejected**: an in-drive in-app picker as the primary
fallback (the phone is locked or showing Google Maps; a notification
reaches the lock screen); shipping without the manifest (App Store
rejection); burying the human-only steps in chat instead of
docs/HANDOFF.md.

## D-017 — App icon and the owner-build Pro override (2026-09-02)

**Chosen**: a generated 1024×1024 app icon (single-size universal entry)
drawn in the app's own trip-detail language — the driver's bold solid
blue route beating Google's dashed orange detour to a checkered finish,
on a navy map grid; and a Pro-tier override for personal device builds:
`scripts/device-build.sh` injects `ROUTEWARRIOR_FORCE_PRO` into
Info.plist as `RouteWarriorForcePro` exactly the way it injects the
Google key, and `StoreService` reports `.pro` when the value is the
exact string "1". The default is empty everywhere (project.yml's base
setting), so CI and any App Store archive are untouched — proven by an
app-target test that asserts the unforced build starts `.free`. The
override can only raise the tier, never mask a real entitlement, and
recording was never gated by tier in the first place (D-008). The Xcode
run scheme also gets `storeKitConfiguration` pointing at the local
`.storekit` file so the real purchase flow is testable in the simulator
before App Store Connect exists. **Rejected**: a DEBUG-only compile
flag (device-build.sh builds Debug today, but the Info.plist route
keeps the behaviour identical if that ever changes, and the empty
default is the actual safety); a hidden in-app unlock gesture (a
public-app foot-gun); granting Pro by hardcoding the tier (would ship
to the store).
