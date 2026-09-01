# Route Warrior — Requirements

Status: v1.0 (approved 2026-09-01). Changes to behaviour described here get a
`DECISIONS.md` entry.

## 1. Problem statement

Drivers who make the same trips repeatedly (commute, school run, weekly
errands) develop their own routes that deviate from Google Maps' guidance —
avoiding stop signs, bad lights, or left turns. Nothing tells them whether
their instincts actually beat Google, by how much, and under what conditions.
Route Warrior records the route actually driven, snapshots what Google planned
at the moment of departure, and turns the history into answers.

## 2. Target user

- Primary: repeat-trip drivers (commuters, parents doing school/childcare
  runs) in the US who use Google Maps but often deviate from it.
- Public App Store product; Brian is user zero and the design reference.

## 3. The questions the app must answer (acceptance queries)

Every one of these must be answerable from the UI for any saved destination
with enough recorded trips. These come verbatim from the product brief:

1. How long did this trip actually take vs. Google's directions (traffic-aware
   ETA at my departure time)?
2. How many stop signs were on my route? How many traffic signals?
3. How was the traffic (actual), and how did it compare to Google's traffic
   assumption?
4. How do my drive times differ by time of day and day of week (and month)?
5. Should I follow Google's directions, or are my routes faster given my
   driving style?
6. Show me my prior trips to this destination; when I drive one of those
   routes again, score me against my prior performance and running averages.

## 4. Functional requirements

### Recording

- **FR-1**: Auto-detect the start of a drive (motion + location) and record
  hands-free at ~1 Hz GPS; auto-end when parked. No interaction required.
- **FR-2**: Manual record/stop as backup, plus "delete this trip" and
  "exclude from stats" (passenger trips, anomalies).
- **FR-3**: Recording works with no network; trips are never lost for lack of
  signal.
- **FR-4**: Per trip, store: full GPS track (timestamped points with speed
  and accuracy), start/end time, timezone, distance, duration, moving vs.
  idle time, detected stop events, origin/destination place, matched route
  variant, recording source (auto/manual).

### Comparison (Google snapshot)

- **FR-5**: At departure, snapshot Google's plan via the Routes API:
  recommended polyline, distance, static duration, traffic-aware duration,
  up to 2 alternates. Requires knowing the destination at departure → FR-6.
- **FR-6**: Predict the destination at trip start from history (origin +
  weekday + time of day). High confidence → snapshot the top prediction;
  medium → snapshot the top two (keep the one matching the actual arrival,
  discard the rest); no confidence → record without a snapshot, and offer a
  one-tap destination pick from the trip-started notification / Live
  Activity.
- **FR-7**: Label each trip "followed Google" vs. "deviated" by polyline
  similarity between the driven track and the snapshot route.

### Places & route history

- **FR-8**: Saved places (home, work, school, custom) with a geofence
  radius; auto-suggest new places from repeated trip endpoints.
- **FR-9**: Cluster trips into route variants per origin→destination pair by
  geometric similarity; auto-name variants ("via Maple Ave"); browse all
  prior trips per destination and per variant.

### Stops & signals (hybrid method)

- **FR-10**: Count traffic signals and stop signs along each variant from
  OpenStreetMap data (Overpass), cached per variant; show a coverage
  confidence note (OSM stop-sign mapping is patchy).
- **FR-11**: Detect actual stop events from the track (halt clusters),
  classify them (stop sign / signal / traffic / unknown) using duration
  heuristics + proximity to OSM nodes; report both "on this route" and
  "times you actually stopped".

### Analytics

- **FR-12**: Per destination and per variant: average / median / best /
  worst time, sample count, breakdowns by day-of-week and time-of-day
  bucket, and month-over-month trend.
- **FR-13**: Actual traffic score per trip (drive time vs. that variant's
  free-flow baseline) compared against Google's assumption (traffic ETA vs.
  static ETA from the snapshot).
- **FR-14**: Verdict card per destination: "your route vs. Google" with the
  time delta and a confidence level; verdicts render only above minimum
  sample counts (initial: ≥ 5 trips per side), otherwise show
  "collecting data (n/5)".

### Ghost race (live, in-drive)

- **FR-15**: During a recognized repeat drive, a Live Activity (lock screen
  + Dynamic Island — Google Maps owns the foreground) shows ahead/behind
  seconds vs. a reference: personal best or personal average for this
  variant (user-selectable default). Glanceable, no interaction while
  driving.

### Monetization (free + Pro subscription, StoreKit 2)

- **FR-16**: Free: unlimited recording, last-30-days history, analytics on 2
  saved destinations. Pro (monthly/annual; prices set at M5): unlimited
  history and destinations, ghost race, full verdict/trend analytics.
  Recording is never gated — data keeps accruing so upgrading is instantly
  valuable. Enforced on-device via TierPolicy; no server.
- **FR-17**: Paywall + restore purchases; family sharing on.

### Onboarding & trust

- **FR-18**: Onboarding explains the always-on location and motion
  permissions before asking (progressive: When-In-Use → Always), states the
  privacy posture in plain language, and demos the payoff with sample data.

## 5. Non-functional requirements

- **NFR-1 Privacy**: trip data exists only on-device and in the user's
  private CloudKit database. No accounts, no LawtonCorp server, no
  third-party analytics/ads SDKs. Only external calls: Google Routes
  (origin/destination coordinates + departure time) and Overpass (padded
  bounding boxes). Both disclosed in the privacy policy; App Privacy label
  targets "Data Not Collected" (we collect nothing — verify the wording
  against Google-call disclosure rules at M6).
- **NFR-2 Schema future-proofing**: stable UUIDs and self-contained records
  so opt-in sharing/leaderboards could be added later without migration
  pain. No sharing features in v1.
- **NFR-3 Battery**: a 30-min recorded drive costs a small single-digit % of
  battery; idle (armed, not driving) drain indistinguishable from baseline.
  Phone-in-hand claim, measured in M2.
- **NFR-4 Accuracy**: recorded distance within ~2% of odometer on clean-sky
  routes; accuracy-filtered (drop points > 50 m horizontal accuracy) and
  smoothed for display.
- **NFR-5 Resilience**: recording survives app suspension/termination (iOS
  relaunches via location updates); iCloud unavailable → local-only with a
  non-blocking warning, sync resumes automatically.
- **NFR-6 Platform**: Swift 6 strict concurrency, iOS 17.0+, US-first (mph,
  US road conventions; units switchable).
- **NFR-7 Kit purity**: every algorithm above lives in the UI-free kit,
  ≥ 90% line coverage, testable via plain `swift test`.

## 6. Non-goals for v1

Turn-by-turn navigation; social features/leaderboards/sharing; CSV/GPX
export; Android; CarPlay; Apple Watch; multi-stop trips; motorcycle/truck
modes; fuel/cost tracking; a backend of ours.
