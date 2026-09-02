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

## D-018 — Colour carries meaning (2026-09-02)

**Chosen**: one small palette (`App/RouteWarrior/Support/Theme.swift`)
built from the vocabulary the trip map and the app icon already teach:
blue is the route you drove, orange is Google's plan, green is a win,
plus indigo for Pro and amber/red for the armed/recording states. Every
use of colour says something — the Home status card tints by recorder
state, trip rows carry a green hare or an orange tortoise from the ETA
delta, places get a glyph per kind, the destination verdict is a tinted
card, stops are coloured by cause — and the mappings are plain functions
with app-target tests so a green row can never mean a loss. The accent
colour moves from the muted indigo to the route blue (with a lighter
dark-mode variant) so tabs, links, and buttons match the map. The
heatmap softens from a green→red stoplight to green→orange, matching the
row palette. **Rejected**: a bespoke dark-navy chrome or themed
backgrounds (flashy, fights the system list styling and dark mode, and
Brian asked for "a bit", not a redesign); decorative per-screen colours
with no meaning (the plainness was the absence of information, not of
paint); touching the Live Activity (it already uses the same green/orange
and is a separate target).

## D-019 — Field test 1: stops must not end drives; make the recorder legible (2026-09-02)

**Trigger**: Brian's first drives with the app (15 and 20 minutes) both
ended in "Trip too brief to keep" and nothing saved.

**Chosen**: (1) A `stationary` motion sample no longer ends a recording —
a car at a red light *is* stationary, and one such sample chopped drives
into sub-3-minute fragments that were each discarded; the 180 s idle
window is the stop rule. Pedestrian motion (walking/running/cycling, ≥
medium confidence) ends the trip immediately only when no point at
driving speed arrived in the last 30 s (`pedestrianEndGrace`); inside
that window it is a suspect that 20 s of sub-driving-speed points
confirm (`pedestrianEndConfirm`) — a driving-speed point dismisses it.
The walk is trimmed from the drive either way. (2) Background location
updates are allowed under When-In-Use as well as Always: the `location`
background mode is declared, and a When-In-Use app keeps updates it
started in the foreground under the system indicator; gating on Always
meant a manual recording lost GPS the moment the phone locked. (3) The
recorder now reports why each recording ended (`EndCause`) and what it
held (`SegmentSummary`: kept points, duration, distance, samples dropped
by the accuracy filter); the Home outcome line carries that detail, and
Settings gains a "Recorder log" (last 40 events, persisted in
UserDefaults so an app kill mid-drive still leaves a trace) with arm,
start, end, permission, and GPS-power events, plus the motion
*authorization* (Settings previously showed only hardware availability).
Thresholds are first guesses to be tuned from that log. **Rejected**:
requiring sustained pedestrian samples (CoreMotion emits on change, so
a second sample may never come — location confirmation is the reliable
witness); ending on any non-automotive sample as before (the bug);
raising `minTripDuration` to mask fragmentation (would keep saving the
fragments, not the drive); a Console/OSLog-only diagnostic (Brian reads
the phone, not Xcode).

## D-020 — Onboarding walks to Always and says what While Using costs (2026-09-02)

**Trigger**: Brian, after the first device build: if hands-free recording
needs Always, setup must say so; a user who picks While Using has to
learn that the app cannot follow their drive.

**Chosen**: the permissions page is driven by the actual grant. Nothing
yet → "Hands-free needs location set to Always" and the While Using
request (iOS insists on that first step). While Using → "One more step:
Always", the consequence in plain words (only drives started with the
Record button while the app is open), and a Change to Always button
that shows iOS's one-time "Change to Always Allow" prompt; a secondary
"Keep While Using — I'll record manually" is the honest opt-out. Because
iOS shows that prompt once per install, the app remembers that it asked
(`alwaysRequested`) and afterwards offers a Settings deep link instead
of a button that would do nothing. Always → "You're set" and the Motion
explanation. Denied → Settings link. The same `LocationPrimer` logic
(pure, tested) drives the Home card, which now warns under While Using
too and carries the fix button, and the Settings row. Motion & Fitness
is no longer requested at first launch: it starts when onboarding
finishes, after its explanation (FR-18 as written). **Rejected**:
requesting Always directly (iOS grants provisional Always and defers the
real question to a random later moment, which is worse for trust and
for support); blocking the app until Always is granted (App Review and
D-008: recording via the Record button is a legitimate While Using
mode); keeping the old copy that called Always an optional upgrade.

## D-021 — New Place: city-scale map and address search (2026-09-02)

**Trigger**: Brian, after adding places: the map opened on the whole
country and the only way to place a pin was to zoom in by hand; there
was no way to type an address.

**Chosen**: the map opens at city scale (about 12 km across) around the
phone's last known fix — `LocationService` now remembers the latest
coordinate from any source and can request a one-shot fix when the form
opens before one exists; until then the camera follows the user with the
old automatic framing as the fallback. An Address field with
autocomplete (`MKLocalSearchCompleter`, addresses and points of
interest, biased to 50 km around the user) and a lookup on tap or return
(`MKLocalSearch`) drops the pin, zooms to about 1.5 km, fills an empty
Name from the result, and writes the resolved address back into the
field. Tapping the map still works and clears the address, since a
hand-placed pin has no verified one. `Place` gains a display-only
`address` (tolerant decoding for records without it; the geofence is
still the coordinate), persisted on `PlaceRecord` and shown under the
name in the Places list. Apple's search was chosen over Google's Places
API because it needs no key, costs nothing, and keeps the privacy label
honest — the only data leaving the phone is the query Apple needs.
**Rejected**: Google Places autocomplete (a second billable key and a
second data flow to disclose for a convenience feature); reverse-
geocoding hand-dropped pins into an address (an invented address on a
pin the user placed deliberately is misleading; leave it blank);
`.userLocation` alone for the camera (its zoom is system-chosen and the
form often opens before a fix exists).
