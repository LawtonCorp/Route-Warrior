# Route Warrior — Specification

Status: v1.0 (approved 2026-09-01). Companion to `REQUIREMENTS.md`; every
feature here traces to an FR/NFR there. Behaviour changes get a
`DECISIONS.md` entry.

## 1. Architecture

```
Sources/RouteWarriorKit/        UI-free logic (no CoreLocation, no SwiftData)
Sources/RouteWarriorStore/      SwiftData @Model layer + CloudKit config
App/RouteWarrior/               SwiftUI app: services, screens, wiring
App/RouteWarriorWidgets/        Widget extension: Live Activity (ghost race)
App/RouteWarriorTests/          wiring tests (one per kit/app boundary feature)
```

- The kit defines its **own value types**; the app converts `CLLocation` at
  the boundary. This keeps the purity gate honest and every algorithm
  fixture-testable.
- `RouteWarriorStore` is a second package target (SwiftData is not a UI
  framework and builds on macOS 14, so `swift test` still works). It maps
  kit value types ↔ persisted models. CloudKit constraints honored: all
  properties optional or defaulted, no `#Unique`, relationships optional.
- Widget extension + app share `group.com.lawtoncorp.routewarrior`; the App
  Group and iCloud/CloudKit entitlements are declared **in `project.yml`
  for both targets** (CLAUDE.md rule — Xcode-UI-set capabilities die on the
  next regeneration, and a missing group fails silently).

## 2. Domain model (kit value types, mirrored in Store)

- `Coordinate` — lat/lon (Double).
- `TrackPoint` — coordinate, timestamp, speedMps, course,
  horizontalAccuracyM.
- `Place` — id, name, coordinate, radiusM (default 75), kind
  (home/work/school/custom), createdAt.
- `Trip` — id, startedAt, endedAt, timezoneID, points `[TrackPoint]`
  (delta-encoded blob in Store; ~70 KB raw per 30-min trip at 1 Hz —
  cheap), originPlaceID?, destinationPlaceID?, variantID?, distanceM,
  duration, movingTime, idleTime, stopEvents `[StopEvent]`, snapshotID?,
  followedPlan `Bool?`, source (auto/manual), excludedFromStats `Bool`.
- `StopEvent` — coordinate, startedAt, duration, cause
  (stopSign/signal/trafficQueue/unknown), matchedOSMNode?.
- `PlanSnapshot` — id, provider (`.googleRoutes`), requestedAt,
  destinationPlaceID, polyline, distanceM, staticDuration, trafficDuration,
  alternates `[AltRoute]` (polyline, staticDuration, trafficDuration).
- `RouteVariant` — id, originPlaceID, destinationPlaceID, representative
  polyline, autoName, tripCount, intersections `IntersectionInventory?`.
- `IntersectionInventory` — signalCount, stopSignCount, coverageConfidence
  (high/medium/low by OSM node density heuristic), fetchedAt.
- `VariantStats`, `DestinationStats`, `Verdict` — winner (mine/google/tie),
  medianDeltaSeconds, sampleCounts, confidence.

All records carry stable UUIDs and are self-contained (NFR-2) so a future
opt-in sharing layer can reference them without a schema migration.

## 3. Kit algorithms

### TripRecorder (FR-1..FR-4)

Pure state machine: `idle → armed` (automotive motion activity, confidence
≥ medium) → `recording` (speed ≥ 4.5 m/s sustained 30 s, or 500 m
displacement) → `ending` (speed < 1 m/s for 180 s, or walking/stationary
motion) → `finalized` (trim trailing idle; discard if < 800 m or < 3 min).
Inputs are abstract `LocationSample`/`MotionSample` events, so the whole
lifecycle is unit-tested with synthetic streams (missed-start, garage cold
start, drive-through idle, red-light-at-end edge cases as named fixtures).

### DestinationPredictor (FR-6)

P(destination | origin place, weekday, 30-min time-of-day slot, first 300 m
bearing). Frequency table with Laplace smoothing over trip history;
confidence = top-1 probability. ≥ 0.6 → one snapshot; 0.35–0.6 → snapshot
top two; below → no snapshot, offer manual pick. Cold start (new user):
manual pick only; prediction kicks in as history accrues.

### RouteMatcher (FR-7, FR-9)

Endpoints match places by geofence; polylines resampled to 64 points;
similarity = symmetric mean point distance; same variant if mean deviation
< 150 m (tunable). The same metric labels `followedPlan` against the
snapshot polyline (threshold 100 m). No match → new variant.

### StopDetector (FR-11)

Cluster consecutive points with speed < 1 m/s lasting ≥ 2 s into
StopEvents. Classification: within 30 m of an OSM `highway=stop` →
stopSign; of `highway=traffic_signals` → signal; duration > 90 s with a
creep pattern → trafficQueue; else classified by duration prior (2–8 s →
stop-sign-like, 8–90 s → signal-like) and reported as inferred.

### StatsEngine (FR-12, FR-13)

Per variant and destination: avg/median/best/worst, day-of-week ×
time-bucket (6 buckets/day, trip-local timezone) matrices, monthly trend.
Traffic score per trip = duration ÷ variant free-flow baseline
(5th-percentile historical time); Google's assumption = trafficDuration ÷
staticDuration from the snapshot; comparing those two ratios answers
acceptance query 3.

### Verdict (FR-14)

For a destination: median actual time on the user's variants vs. (a) median
actual time on trips that followed Google and (b) Google's traffic ETAs.
Needs ≥ 5 samples per side; confidence derives from sample size and
variance. Copy is honest: "Your route via Maple Ave beats Google's plan by
~2:10 in the morning bucket (12 trips vs 7)."

### GhostRaceEngine (FR-15)

Project the live position onto the variant polyline →
distance-along-route → compare elapsed vs. the reference trip's elapsed at
the same distance → ahead/behind seconds. Reference: personal best or
bucket average (setting). Pure function of (polyline, reference profile,
live sample); Live Activity updates every ~15 s or 200 m.

### TierPolicy (FR-16)

Pure gate: given entitlement + counts, what's accessible. All limits live
in one place and are unit-tested.

## 4. App services

- **LocationService** — CLLocationManager + CMMotionActivityManager feeding
  TripRecorder. Armed mode uses significant-change + visit monitoring +
  motion (near-zero battery); recording mode uses best accuracy, background
  updates on, auto-pause off. Handles relaunch-after-termination.
- **SnapshotService** — Routes API `computeRoutes` (field-masked POST,
  TRAFFIC_AWARE, alternatives). API key restricted to the iOS bundle ID +
  hard quota caps + billing alarms. Cost order of magnitude: ~2 calls/trip
  → ~250 calls per heavy user per month (~$1–3/user/month at list beyond
  the free tier — verify current pricing/SKUs at M3). A keyless proxy is
  the post-v1 escape hatch if abuse or scale demands it.
- **OverpassService** — per new variant, query signals/stop signs in a
  padded corridor bounding box (privacy: a padded box, not the exact
  polyline); cache in IntersectionInventory; retry queue when Overpass is
  down; counts show "pending" until fetched. Respect public-instance rate
  limits; a self-hosted mirror is the scale escape hatch.
- **StoreService** — StoreKit 2 subscription ("pro" entitlement), monthly +
  annual, intro offer decided at M5.
- **ActivityService** — ActivityKit lifecycle for the ghost race.
- **SyncMonitor** — surface CloudKit state (off/ok/error) in Settings.

## 5. Screens

1. **Onboarding** — value demo with sample data → privacy statement →
   permission primers (When-In-Use → Always upsell, Motion, Notifications).
2. **Home** — recording status, today's trips, streak-style quick stats.
3. **Trips** — list, filterable by destination; badges: no-snapshot,
   deviated, excluded.
4. **Trip detail** — map with actual (solid) vs. Google (dashed) polylines;
   stat row: time vs. ETA delta, stops, signals, idle time, traffic score;
   stop-event timeline; followed/deviated label; exclude/delete.
5. **Destinations** — saved places + auto-suggested new ones.
6. **Destination detail** — verdict card, variants with per-variant stats,
   day×time heatmap, monthly trend, full history.
7. **Ghost race** — Live Activity layouts (lock-screen banner + Dynamic
   Island compact/expanded): ahead/behind delta, reference label, progress.
8. **Settings** — subscription, permissions status with fix-it links, ghost
   race reference choice, units, delete-all-data, privacy policy.
9. **Paywall** — feature table, prices, restore.

## 6. Edge cases (spec'd behaviors, tested where machine-checkable)

- Offline at departure → trip records, "no comparison" badge (FR-3).
- Wrong/missing destination prediction → comparison absent; one-tap pick at
  start via notification; never blocks recording.
- Missed auto-start → manual button; late-start trips flagged so verdicts
  don't ingest truncated times.
- Passenger/bus trips → exclude-from-stats; v1 documented limitation (no
  automatic passenger detection).
- iOS kills the app mid-trip → relaunch on location update, stitch
  segments; a gap > 5 min splits the trip.
- Urban-canyon GPS noise → accuracy filter + smoothing before matching.
- Overpass down → pending counts, background retry.
- iCloud full/unavailable → local-only + warning; no data loss.
- DST/timezone travel → store UTC + timezone id; buckets computed in
  trip-local timezone.
- Low Power Mode → record, but note degraded sampling on the trip.

## 7. App Review & compliance plan

Always-location apps get extra scrutiny: purpose strings that name the user
benefit, in-app education before prompting, and a review-notes walkthrough
+ demo video (M6). `PrivacyInfo.xcprivacy` with required-reason APIs (user
defaults, file timestamps), location + motion usage descriptions, privacy
policy URL, and a "Data Not Collected" label (validated at M6). Background
modes: `location`. No IDFA, no tracking, no third-party analytics SDKs.
