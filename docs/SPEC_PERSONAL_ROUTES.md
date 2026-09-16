# Personal routes at departure — draft spec (v1.1 candidate)

_Status: APPROVED 2026-09-16 (Brian's answers in §8, logged as D-065).
Numbering continues docs/REQUIREMENTS.md and SPEC_IN_APP_MAP.md (FR-25+).
Building for v1.0 — Brian's call, over the sequencing concern in §9.
Slice 1 landed as D-065 (#69); slice 2 (FR-25/26/27) as D-066 (#70);
slice 3 (§4.5) as D-067. Pre-selection (slice 4) is not built (§8.2)._

## 1. Goal

The app exists so a driver can choose the best route to a place they go
often — their own, Apple's or Google's — using what has actually
happened on their drives: which road, what time, which day. Today the
Plan tab offers only the providers' plans, and the driver's own routes
appear only as history on the Destination screen. Nobody can *act* on
"Maple Ave is usually faster on weekday mornings" at the moment it
matters, which is with the engine running.

This spec puts the driver's own routes on the Plan tab as choices,
recommends one for *now* rather than in general, and keeps every
guarantee the app already makes — above all D-010: the verdict is
measured against the plan you left with.

## 2. What already exists

Most of the analysis is built. This is conditioning and surfacing, not
a recommender from scratch.

| Piece | What it does today |
|---|---|
| `RouteVariant` | One distinct way of driving an origin→destination pair: representative polyline, auto name ("via Maple Ave"), the driver's own name, `tripCount`, OSM signal and stop-sign inventory |
| `RouteMatcher` | Clusters every finished trip into a variant by shape (150 m mean deviation), founding a new variant when nothing matches |
| `RouteRaceEngine` | Ranks the driver's variants against each other by median duration, with a 30 s tie margin, a 3-drive floor per route, and medium/high confidence at 8 |
| `StatsEngine.weekdayBucketMatrix` | Duration stats per (weekday × 4-hour bucket), in each trip's own time zone — the time-of-day data, already computed |
| `DestinationPredictor` | The (weekday, 30-minute slot) context with backoff to coarser cells below `minCellSamples` — the sparse-data pattern, already solved once |
| `PlanList` (D-063) | The Plan tab's route list: fixed order, a pick marked with a check, the pick applied once to the departure snapshot |

`RouteRaceEngine` is surfaced only on the Destination screen, as a
head-to-head over all drives. It does not know what time it is, and it
is not offered at departure.

## 3. The four gaps

1. **The race ignores the clock.** `RouteRaceEngine.race` pools every
   drive. A route that wins at 10am can lose at 8am, and rush hour is
   exactly when the choice matters.
2. **Personal routes are not offered at departure.** The Plan tab shows
   provider plans only.
3. **What is the baseline when you drive your own route?** D-010 says the
   verdict is against the plan you left with. A variant has no provider
   ETA.
4. **A personal route has no turn-by-turn.** D-052 guidance is built from
   provider steps; a variant carries a polyline and nothing else.

## 4. Design

### 4.1 Gap 3 first: the baseline does not move (D-010 holds unchanged)

When the driver picks their own route, the app **still fetches and stores
the provider snapshot at departure** and it is still the baseline. The
driver departs on their road; they are measured against Google's plan.
The verdict reads "your route beat Google's plan by 3:20" — which is the
sentence the app exists to produce.

A personal route changes what the driver **drives**, not what they are
**judged against**. The scoreboard, the ghost race, the departure
snapshot and every verdict rule keep working with no change.

Secondary, later: "and 40 s faster than your usual on this road", from
the variant's own median. It is a different comparison and must be
labelled as one.

**Rejected**: making the variant's median the baseline (answers "faster
than my usual", not "faster than the nav" — the app's question); asking
the provider for an ETA along the personal polyline as waypoints (an
extra billed call per departure for a number the verdict does not use).

### 4.2 Gap 1: time-conditioning with an honest backoff

Slicing by (weekday × 4-hour bucket) shreds the sample. Twelve school
runs across three routes is four each; "Tuesday 8am–noon" may leave one.
`RouteRaceEngine` already refuses to call a race below three drives per
route, and under a hard slice it would refuse almost every time.

So the recommendation backs off, the way `DestinationPredictor` does for
sparse cells, and **the tier that answered is part of the answer**:

| Tier | Drives counted | What the screen says |
|---|---|---|
| 1 | This weekday, this slot | "usually fastest on Tuesday mornings" |
| 2 | Weekday-or-weekend, this slot | "usually fastest on weekday mornings" |
| 3 | This slot, any day | "usually fastest at this time of day" |
| 4 | Every drive | "usually fastest" |

Each tier runs `RouteRaceEngine.race` over its own subset of trips and
takes the first tier that returns a `.winner`. A `.tie` at a narrow tier
is not a reason to widen: the honest statement is "no clear winner on
Tuesday mornings", and the wider tiers are reported beneath it as
context, never as the headline. "Fastest on Tuesday mornings" and
"fastest overall" are different claims; a comparison app that blurs them
loses the trust it is selling.

New kit type, pure, testable without a phone:

```swift
public enum RouteRecommender {
    public struct Context { weekday: Int; slot: Int; timezoneID: String }
    public enum Tier { case weekdaySlot, dayClassSlot, slot, all }
    public struct Recommendation {
        var race: RouteRaceEngine.Race   // the routes and outcome at that tier
        var tier: Tier                   // which claim this is
        var drivesCounted: Int
    }
    public static func recommend(variants:trips:now:config:) -> Recommendation?
}
```

Slot width is a config question (§8.3). The 4-hour buckets already in
`StatsEngine` are the default; 30-minute slots like the predictor's are
too fine for route stats at any realistic sample size.

### 4.3 Gap 2: the Plan tab

D-063 made the route list a fixed, pickable list with a check. Personal
routes become **additional rows in that same list**, ahead of the
provider's, when there are any:

```
◉ Your way — via Maple Ave     18:40   6.7 mi
    usually fastest on weekday mornings · 9 drives
○ Your way — the back way      20:05   6.7 mi
    no clear winner on weekday mornings · 4 drives
○ Google's plan                19:36   7 mi
○ Google Alt 1                 19:19   6.7 mi
```

- The time on a personal row is the **median at the answering tier**,
  labelled as usual-not-predicted (the provider's number is a traffic
  forecast; ours is history).
- The map draws the picked route's line, as it draws a picked alternate
  today.
- Personal rows appear only when **both origin and destination resolve to
  known Places with at least one matched variant**. A typed address with
  no history shows the provider list exactly as today.
- Whether the app pre-selects a personal route or only offers it is §8.2.

### FR-25 — Personal routes as departure choices

Given a destination that is a known Place with matched variants from the
current origin Place, the Plan tab lists each variant as a pickable row
with its display name, its usual duration at the answering tier, its
distance and turn count, and the recommendation line. Picking one draws
its polyline; Go departs on it. The provider snapshot is still taken and
stored as the baseline (D-010).

### FR-26 — Recommendation is time-aware and says so

The recommendation line names the tier it was computed at. A tie at the
narrowest tier with enough data is reported as a tie, not widened into a
win.

### 4.4 Gap 4: no spoken guidance on your own route — and that is the right answer

Three options were weighed:

- **None.** The map draws the line, the scoreboard runs, the banner stays
  quiet.
- **Provider directions along the polyline as waypoints.** One more
  billed call per departure; snapping a driven track to a provider route
  is imperfect and fails loudest on exactly the shortcuts that make a
  personal route worth having.
- **Synthesise maneuvers from geometry.** `TurnCounter` already finds
  turns in a track, but with no street names, and spoken instructions
  invented from geometry while someone is driving is not a thing to ship.

**Chosen: none, in v1.1.** The justification is real rather than an
excuse: it is the driver's route because they already know the way.

### FR-27 — Driving a personal route

On Go with a personal route picked, the drive view shows the picked line
and the scoreboard against the provider baseline; the maneuver banner and
spoken callouts are off; off-plan detection (`OffPlanDetector`) runs
against the personal polyline so leaving the route is still noticed.

### 4.5 Slice 3: the verdict names both roads

The trip verdict today says "you beat Google's plan by 3:20". With a
personal route picked it should say "via Maple Ave beat Google's plan by
3:20", so the Trips list becomes evidence for the choice rather than a
list of wins. `Trip.variantID` already carries which road; this is
wording.

## 5. Non-goals (this round)

- Recommending a route the driver has **never** driven (that is the
  providers' job, and they are already on the list).
- Predicting a personal route's duration from live traffic (we have
  history, not a traffic model; the provider row carries the forecast).
- Turn-by-turn on personal routes (§4.4).
- Learning from other users. Everything is on-device and private (D-006);
  nothing here changes that.

## 6. Architecture

- **Kit**: `RouteRecommender` (new, pure). Depends only on
  `RouteRaceEngine`, `StatsEngine.cell(for:)` and the trips. No UI, no
  store, no clock — `now` is a parameter.
- **App**: `DrivePlanner` learns to hold personal routes alongside
  provider plans; `PlanList.rows` grows a `.personal(variantID)` row kind
  ahead of the provider rows; `HomeView.go()` starts the drive with the
  variant's polyline as the driven line and the provider snapshot as
  baseline. `RecordingPipeline.startPlannedDrive` gains a way to say
  "driving this variant" so `RouteMatcher` and the verdict can name it.
- **Store**: `TripRecord` may gain `chosenVariantID: UUID?` (additive,
  defaulted, CloudKit-safe) so "what did I pick" survives separately from
  "what did the matcher decide I drove". Nothing else changes.
- **Tests**: the recommender's ladder, tie handling and tier wording in
  the kit; the row order, gating and departure-snapshot rule in
  `PlanListTests`; a store round-trip for the new field.

## 7. Milestones

| Slice | Delivers | Verifiable by CI |
|---|---|---|
| 1 | `RouteRecommender` in the kit; the recommendation as a text line on the Destination screen | Fully — every rule is pure |
| 2 | Personal routes as Plan-tab rows (FR-25, FR-26), drawn on the map, departing with the provider baseline | Rules yes; the screen needs a phone |
| 3 | Verdict wording names the road (§4.5) | Fully |
| 4 | Pre-selection, if §8.2 says so | Rules yes |

Slice 1 is the whole algorithm. Slices 2–4 are wiring.

## 8. Decisions (Brian, 2026-09-16 — D-065)

1. **Pro.** Both the recommendation line and personal routes as
   departure choices. (Recommended split — insight free, acting Pro —
   not taken; the whole feature is Pro.)
2. **Offer.** The check lands on the provider's plan; personal routes
   are listed above it and chosen by hand. Pre-selection is not built.
3. **Five drives per route, at every tier.** A flat floor rather than
   the 3/4/5 ladder proposed; one `RouteRecommender.Config` value. The
   all-time race on the Destination screen keeps `RouteRaceEngine`'s
   floor of three — it makes a different, wider claim.

   **Revised twice on 2026-09-16.** First to a flat four (D-070), then
   to the **3/4/5 ladder this section originally proposed** (D-071):
   five at tier 1, four at tier 2, three at tiers 3–4. The ladder is
   what the code carries; five-flat is what this section recorded on
   the day, and is left standing as the decision that was made then.

## 9. Sequencing

**Building for v1.0, on Brian's decision (2026-09-16).** The
recommendation here was 1.0 first and this as 1.1, because the feature
is invisible on a fresh install: a new user has no variants, so there is
nothing to recommend, it cannot be shown in the App Review video, and it
only becomes real as drives accumulate. Brian weighed that and chose to
ship it in 1.0. Consequences to carry: the review video shows the
feature on Brian's own history (the only account with any), and the
listing describes it as something the app grows into rather than shows
on day one.

## 10. Risks

- **Small samples that look like signal.** Three drives is a floor, not
  a proof; the tier wording and the drive count on every row are the
  mitigation, and §8.3 sets the floors.
- **Variant drift.** If `RouteMatcher` splits one habitual route into two
  variants over noisy GPS, the race is between two halves of the same
  road. Existing risk, made visible by this feature; watch the variant
  count per destination in Brian's data before slice 2.
- **The pick disagreeing with the matcher.** The driver picks "via Maple
  Ave", drives it, and the matcher files the trip under a different
  variant. `chosenVariantID` keeps both facts; the verdict wording uses
  the matcher's answer and the Trips screen can show the disagreement.
