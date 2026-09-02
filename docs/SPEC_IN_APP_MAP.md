# In-app map and routing — draft spec (v2 candidate)

_Status: APPROVED 2026-09-02 (answers in §9, logged as D-022). M7 in
progress. Numbering continues docs/REQUIREMENTS.md (FR-19+). This revisits the v1
non-goal "turn-by-turn navigation in-app" (D-003) deliberately: v1 proved
the recording and comparison engine; v2 lets the driver see the plan
inside Route Warrior instead of in another app._

## 1. Goal

Pick a destination in Route Warrior, see the planned route from the
provider you prefer (Apple or Google) on a map inside the app with live
traffic, then drive with that map following you — taking the suggested
route or leaving it — while everything v1 does (recording, the departure
snapshot, the verdict, the ghost race) keeps working unchanged.

The product promise does not move: Route Warrior still *proves whose way
is faster*. The map is where the driver watches the proof happen.

## 2. What each provider can actually do

Facts first, because the two are not symmetric. Items marked **verify**
could not be confirmed from this environment (Google's developer pages
are blocked here) and need a look on the Mac before M8 starts.

| Capability | Apple (MapKit) | Google (Maps SDK for iOS) | Google (Navigation SDK) |
|---|---|---|---|
| Map inside the app | Native SwiftUI `Map`; already used | `GMSMapView` via `UIViewRepresentable`; Swift Package available | Part of the Navigation SDK |
| Route + ETA | `MKDirections`: polyline, steps, `expectedTravelTime` (traffic-aware), up to 3 alternates. Free, no key, rate-limited | Routes API (already integrated, D-001/D-013): polyline, static + traffic-aware durations, alternates, per-step instructions. Billed per call | Included, per-destination billing |
| Live traffic overlay | `showsTraffic` on the map style. Free | `isTrafficEnabled`. Free | Yes |
| Voice / lane guidance, automatic reroute | **None.** MapKit has no guidance API; anything beyond drawing the route and steps is ours to build | **None** in the Maps SDK | Yes — Google Maps-grade turn-by-turn |
| Access / cost | Apple Developer Program only | API key with "Maps SDK for iOS" enabled; map loads on mobile are **verify**: believed free of charge | **Verify**: believed to require a Mobility agreement with Google and per-destination pricing; not a drop-in |
| Privacy | No third-party SDK; label stays "Data Not Collected" (D-006, D-016) | Google's SDK ships its own privacy manifest and reports usage to Google → the App Privacy label **changes** and the policy must disclose it | Same, more so |
| Terms on mixing | Apple map data is meant for Apple maps | Embedding is allowed through the official SDK with attribution and branding intact and an authorized key (Brian, 2026-09-02). Google content on a *non-Google* map is the thing to avoid — so Google's line is drawn only on the Google surface, which also changes v1's trip detail (see §9.2) | n/a |

Conclusions this spec is built on:

1. **Each provider's route is shown on that provider's own map.** Apple
   mode = Apple map + Apple directions. Google mode = Google map + Google
   Routes. That keeps both sets of terms clean and is what users expect
   the two modes to look like anyway.
2. **Turn-by-turn voice guidance is out of scope for both** in the first
   two milestones. Apple cannot do it at all; Google can only through the
   Navigation SDK, which is a separate commercial track. What both *can*
   do is the thing this app needs: the route drawn, your position on it,
   traffic, the ETA, and "you are off the plan".
3. **Apple mode costs nothing and changes no privacy disclosure**, so it
   ships first (M7). Google mode (M8) is gated on the two **verify** items
   and on the privacy decision in §9.

## 3. Product behaviour

### FR-19 — Map provider preference
- A setting, "Map & routes: Apple / Google", shown in Settings and as a
  new onboarding page ("Whose routes do you want to beat?"). Stored
  locally; synced with the user's other devices via the same private
  CloudKit store as everything else.
- Google is offered only when the build has a Google key; keyless builds
  (CI, and any user build without the key) silently offer Apple only.
- Changing the preference affects *future* drives. Existing trips keep
  the provider their snapshot was taken from.

### FR-20 — Choose a destination and preview the plan
- From Home: "Where to?" → a saved place, or the D-021 address search.
- The Plan screen shows the preferred provider's map centred on the
  route: the primary route as the provider's line, alternates as thinner
  lines, ETA and distance for each, the traffic layer on. Tapping an
  alternate makes it the plan.
- "Go" arms the trip: recording starts as a *manual-source* trip if the
  car is not yet moving, and the chosen route becomes the departure
  snapshot (FR-5) for that trip — from the chosen provider. The Google
  path is the existing `RecordingPipeline` snapshot; the Apple path is a
  new `AppleDirectionsClient` behind the same `RoutesProviding` seam.
- A destination the predictor would have picked is still predicted for
  auto-detected drives (FR-6) — this screen is the *explicit* path, not a
  replacement for hands-free.

### FR-21 — Drive view
- Full-screen map, camera following the car (course-up while moving,
  north-up when stopped), the plan drawn, your trail drawn in the app's
  route blue as it grows, traffic on, ETA and the live ahead/behind delta
  from the ghost race in a glanceable banner. Screen stays on while this
  view is up. Nothing needs a tap while moving.
- The Live Activity (FR-15) keeps running underneath, so locking the phone
  or switching to music loses nothing.
- Available to any recording drive: one opened from the Plan screen, or an
  auto-detected drive the user opens the app during.

### FR-22 — Off the plan
- The kit already measures deviation from a polyline corridor
  (`RouteMatcher.liveMatch`, D-014). When the car is more than
  *N* metres off the plan for more than *T* seconds, the banner says
  "Off the plan — your way" and the trail line changes to the win green.
- **The departure snapshot is never replaced.** Proving your way is the
  product; the baseline stays what the provider said when you left.
- Optional reroute: a "Reroute" button asks the provider for a fresh plan
  from the current position and draws it as a *second* line; the verdict
  still compares against the original. (Google: one extra billed call per
  tap. Apple: free.) Whether reroute is automatic, on-tap, or off is a §9
  question.

### FR-23 — Verdicts per provider
- `PlanSnapshot.Provider` gains `appleMaps`. Trips, variants and the
  verdict engine already key on the snapshot; the destination screen shows
  one verdict card per provider that has enough data ("Your route vs.
  Apple", "…vs. Google"), each with its own sample thresholds (FR-14).
- Optional "beat both": at departure, snapshot *both* providers regardless
  of preference so every trip contributes to both verdicts. Costs one
  Google call per trip even in Apple mode. §9 question.

### FR-24 — Hands-free unchanged
- Auto-detected drives keep the D-010/D-013 behaviour, with the snapshot
  fetched from the preferred provider. The drive view is one tap away if
  the user opens the app.

## 4. Non-goals (this round)

- Voice turn-by-turn, lane guidance, speed-limit display. Apple has no
  API; Google needs the Navigation SDK. Revisit as M9 if wanted.
- Offline maps. CarPlay (its navigation entitlement needs Apple's
  approval and a separate UI; a later milestone if the drive view earns
  it). Landscape layouts.
- Replacing the departure snapshot on reroute (see FR-22).

## 5. Architecture

- **Kit (UI-free, unchanged rule D-009):**
  - `PlanSnapshot.Provider += .appleMaps`; `PlanSnapshot` gains an
    optional `steps: [PlanStep]` (instruction text, distance, polyline
    segment) so a step list can be shown without a provider call.
  - `RoutesProviding` stays the seam. `AppleDirectionsClient` (app layer,
    MapKit) converts `MKRoute` into `PlanSnapshot`; the kit gets a
    provider-neutral fixture test for the conversion (external expected
    values, per the verification rule).
  - `OffPlanDetector` over `liveMatch`: pure, timestamp-driven, tested with
    synthetic tracks (thresholds *N*, *T* in a `Config`, tuned from the
    recorder log).
  - `MapPreference` value type in the kit; `TierPolicy` learns which map
    features are Pro (§9).
- **App:**
  - `MapSurface` protocol with two views: `AppleMapSurface` (SwiftUI
    `Map`) and `GoogleMapSurface` (`UIViewRepresentable` over
    `GMSMapView`). Both render one `MapScene` value: camera, plan lines,
    trail, markers, traffic flag. Screens never touch a provider type.
  - `PlanScreen`, `DriveScreen`, provider picker in Settings and
    onboarding.
  - Google Maps SDK via Swift Package in `project.yml`, key from
    Info.plist (the existing key, with "Maps SDK for iOS" enabled on it —
    a HANDOFF step). `PrivacyInfo.xcprivacy` updated with Google's
    declared collection; App Privacy label and privacy policy updated.
- **Tests (CLAUDE.md rule):** kit tests for conversion, off-plan
  detection, per-provider verdicts; app-target tests for the preference
  wiring, the snapshot-from-chosen-provider path, and the keyless
  fallback to Apple.

## 6. Milestones

- **M7 — Apple in-app map.** FR-19 (Apple only, picker present but with one
  option), FR-20, FR-21, FR-22 (off-plan + on-tap reroute), FR-23
  (per-provider verdict, Apple snapshots), FR-24. No new dependencies, no
  privacy change, no cost. Field test: a week of driving from the Plan
  screen.
- **M8 — Google in-app map.** Maps SDK, `GoogleMapSurface`, Google mode in
  the picker, privacy manifest/label/policy, key scope, HANDOFF steps.
  Gated on the two **verify** items and the privacy answer.
- **M9 (optional) — Guidance.** Next-turn banner and step list from the
  provider's steps (both providers); Navigation SDK evaluation for Google
  voice guidance.

## 7. Costs

- Apple: $0 beyond the developer program.
- Google: Routes API calls as today (one per trip, two for "beat both",
  plus one per reroute tap); Maps SDK map loads **verify** (believed free);
  Navigation SDK — commercial agreement, only if M9 goes that way.

## 8. Risks

- **Privacy label.** Adding Google's SDK ends "Data Not Collected". This is
  a product decision, not a technical one (§9 Q3).
- **Terms.** If Google's terms forbid its routes on a non-Google map, v1's
  trip-detail overlay already needs fixing (draw Google's line only on
  the Google surface, or as a schematic comparison rather than on a map).
- **Battery.** A following map at 1 Hz GPS is normal nav-app draw; the
  Live Activity remains the low-power option. NFR-3 is re-measured.
- **App Review.** A drive view invites the "navigation app" checklist:
  Always-location justification (already in APP_REVIEW_NOTES), and a
  statement that guidance is visual only.

## 9. Decisions (Brian, 2026-09-02 — D-022)

1. **Guidance depth: (a).** Map, route, your dot, ETA, off-plan signal. No
   voice. Next-turn banner and step list stay M9.
2. **Google map surface: (a) the Maps SDK.** Google's routes are drawn on
   Google's map, Apple's on Apple's. Brian's reading of Google's embedding
   requirements (official SDK, attribution and branding untouched, an
   authorized key on a billing account) is the compliance basis for M8.
   Consequence for every screen with a map, including v1's trip detail:
   **a provider's plan line is drawn only on that provider's surface.**
   The other provider appears as numbers (ETA, delta) and in its verdict
   card, never as a line on the wrong map.
3. **Privacy: (b).** Accept the App Privacy label change for Google mode.
   `PrivacyInfo.xcprivacy`, the questionnaire, and the policy are updated
   in M8, when the SDK actually ships.
4. **Default provider: (a) Apple.**
5. **"Beat both": yes.** Every departure snapshots both providers when a
   Google key is present; each trip feeds both verdicts.
6. **Off the plan: (b) now, built for (c).** Reroute on tap in M7, drawn as
   a second line; an "Reroute automatically" setting (default off) drives
   the same code path with a throttle. The departure snapshot is never
   replaced.
7. **Pro gating: (a).** Plan preview free; drive view and reroute Pro.
8. **Order: yes.** M7 (Apple) ships and field-tests first. Brian verifies
   Maps SDK map-load pricing on the Mac before M8 (click steps given in
   chat).
