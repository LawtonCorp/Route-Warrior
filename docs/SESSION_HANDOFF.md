# Session handoff — state of Route Rebel as of 2026-09-10

_Audience: the next AI coding session (and future Brian). The human-only
checklist lives in `docs/HANDOFF.md`; this file is everything else — what
exists, why, and what the previous sessions learned the hard way. Read
`CLAUDE.md` first; it is binding. Product rationale is in
`docs/REQUIREMENTS.md`, `docs/SPEC.md`, `docs/SPEC_IN_APP_MAP.md`,
`docs/BUILD_PLAN.md`, and every behaviour choice is logged in
`DECISIONS.md` (D-001…D-051; continue from D-052)._

## Where things stand

**The app is called Route Rebel** (display name only, D-030). The repo,
modules, bundle id `com.lawtoncorp.routewarrior` and CloudKit container
`iCloud.com.lawtoncorp.routewarrior` keep the old name on purpose: a
bundle-id change would orphan the App Store record, the provisioning and
every user's CloudKit data. Do not rename them unless Brian asks.

**Fifty PRs have landed; `main` is green at #50; there are no open PRs,
no unpushed work and no scheduled check-ins.** Brian is preparing the
App Store submission. He builds to his phone with
`./scripts/device-build.sh` from `/Users/roar/Route-Warrior`.

What the app does today: auto-records drives hands-free, or from a
plan; the **Plan tab** opens with the "Where to?" field, the map under
it, the plan rows (ETA, distance, turn counts) under the map, saved
places under those; Record is a nav-bar button while nothing else would
start a drive, and a one-row recorder ("Rec" with a blinking dot, Drive
view, Stop) appears beneath the routes only while armed or recording;
plans are snapshotted at departure — Apple's for everyone, Google's for
Pro (D-050); the drive is compared against them; stop signs/signals from
OpenStreetMap; turns counted from the line itself, lefts apart (D-043),
on trips, routes and each plan; per-destination verdicts, heatmap,
trend, and a race between the driver's own routes; a lock-screen ghost
race; a live scoreboard on the drive view; Apple Maps hand-off for
CarPlay guidance; private CloudKit sync; StoreKit 2 Pro at $3.99/month
or $24.99/year with a 7-day trial on both; a Terms of Use and Privacy
Policy linked from Settings, the paywall and onboarding.

## This session (2026-09-09/10), PR by PR

| PR | What | Decision |
|---|---|---|
| #42 | Turn counter: `TurnCounter` (kit), on trips, routes, race rows, plan rows | D-043 |
| #43 | Go never waits for plans; Record hides behind a destination; manual Record predicts its destination | D-044, D-045 |
| #44 | Plan tab layout: "Where to?" first, status card gone, Record in the nav bar, recorder row beneath routes | D-046 |
| #45 | Recorder row as its own card, "Rec" + `BlinkingDot`, inline title | D-047 |
| #46 | Cartoon icon (superseded the same day) | D-048 |
| #47 | Brian's icon: yellow arrow + violet ghost, light/dark/tinted, sources in `design/` | D-049 |
| #48 | Tier line: Google is Pro, free never calls Google, deep analytics/trip detail/sort-filter Pro, `ProLock` blur, counted paywall, StoreKit prices + trials | D-050 |
| #49 | Terms of Use, `Legal`, links in Settings/paywall/onboarding, acceptance recorded | D-051 |
| #50 | Legal links point at routerebel.app | — |

Brian's field-test reports drove #43–#45 (screenshots with one-line
notes). He has **not yet reported** on: turn counts on real drives,
the blurred Pro sections, the paywall counts, or the trial line.

## Layout (the 30-second map)

- `Sources/RouteWarriorKit/` — ALL logic, UI-framework-free (enforced by
  `scripts/kit-purity-gate.sh`; also no CoreLocation/SwiftData/MapKit/
  WidgetKit/ActivityKit). Geo/Polyline (E5), TripRecorder, StopDetector,
  RouteMatcher, DestinationPredictor, StatsEngine, VerdictEngine,
  GhostRace, LiveMatch, RoutesProviding, Overpass, RouteRaceEngine
  (now carries `turns`), DriveScoreboard, ArrivalDetector, Place.Kind,
  **TurnCounter** (`Turn`, `TurnCount`, `turns(along:)`, `count(for:)`,
  `typical(for:)`), **TierPolicy** (+ `googleComparisonAvailable`,
  `snapshotProviders(for:available:)`, `deepAnalyticsAvailable`,
  `fullTripDetailAvailable`, `tripOrganizerAvailable`).
- `Sources/RouteWarriorStore/` — SwiftData @Model records + mapping +
  `StoreFactory`. Unchanged this session (nothing new is persisted).
- `App/RouteWarrior/Services/` — RecordingPipeline (now takes `tier:`
  and `policy:`; `snapshotProviders` filters every provider call;
  `adoptDeparturePlans` for plans landing after Go; manual Record
  predicts on its first sample), LocationService, GoogleRoutesClient,
  DrivePlanner (`goTitle`), AddressSearch, MapSettings,
  AppleMapsHandoff, StoreService (unchanged; tier authority).
- `App/RouteWarrior/Support/` — MapScene, SuggestionDetail,
  TripOrganizer, ScoreboardText, LastMapCenter, DestinationAnalytics,
  HistoryGate, Format, Theme (+ `BlinkingDot`), **TurnText**,
  **HomeLayout** (Record/recorder-row visibility rules),
  **LockedDataSummary** (paywall counts), **PaywallText**, **Legal**
  (URLs, Terms version, acceptance key).
- `App/RouteWarrior/Views/` — HomeView (Plan tab; inline title; toolbar
  Record; `recorderRow`; free-tier Google notice), DriveView, TripsView
  (sort/filter gated), TripDetailView (turns/stops/destination link
  gated), DestinationDetailView (heatmap/trend/race gated via
  `ProLock`), VariantDetailView (left/right turn rows), PaywallView
  (rewritten: features, counted locked data, trial lines, legal links),
  SettingsView (legal links in About), OnboardingView (acceptance line),
  **ProLock** (`ProLock`, `ProLockRow`), the map surfaces, Places.
- `App/RouteWarriorTests/` — 30 files. New: TurnTextTests,
  HomeLayoutTests, ProGateWiringTests, LockedDataSummaryTests,
  LegalTests; DrivePlannerTests, RecordingPipelineTests,
  SnapshotWiringTests extended.
- `Tests/RouteWarriorKitTests/` — new TurnCounterTests + `TurtleTrack`
  (a shared track generator: straight legs and arcs of known radius);
  RouteRaceEngineTests and TierPolicyTests extended.
- `design/` — `AppIcon-light.svg`, `-dark.svg`, `-tinted.svg` and a
  README. The asset catalog's `Contents.json` declares iOS 18
  `appearances` for the three 1024 PNGs.
- `docs/TERMS_OF_USE.md`, `docs/PRIVACY_POLICY.md` — served by the
  marketing site at `routerebel.app/terms` and `/privacy`.
- `App/RouteWarrior/RouteWarrior.storekit` — group "Route Rebel Pro",
  $3.99 / $24.99, `introductoryOffer` `{paymentMode: free, P1W}` on
  both.

## Decisions with teeth (details in DECISIONS.md)

- **D-022**: a provider's plan is drawn only on that provider's map
  surface. The departure snapshot is never replaced by a reroute.
- **D-034**: CarPlay guidance is Apple Maps via hand-off. Apple's
  navigation entitlement was judged unattainable; the *driving-task*
  entitlement is requested per `docs/HANDOFF.md`. **Turn-by-turn is the
  next session's first question — see What's next.**
- **D-043**: turns from the line's shape: resample 5 m, heading over
  ±20 m, 45° opens, 20° closes, ≥135° is a U-turn; trips drop halted
  (<1 m/s) and poor (>50 m) samples first. Corners up to r≈25 m count,
  long bends up to r≈50 m; a wide-median U-turn reads as a left. Nothing
  persisted. `TurnCounter.Config` is the tuning knob.
- **D-044**: Go is never disabled while plans load; a plan requested
  before departure that lands after Go is adopted into a plan-less
  drive; a drive with plans never has them replaced (D-010).
- **D-045/046/047**: one start button at a time; the recorder speaks
  only while doing something; manual Record predicts its destination.
- **D-049**: the icon is Brian's. Do not redraw it.
- **D-050**: the tier line. Free = record forever, 30 days, 2
  destinations, Apple comparison, driven line, plan preview with turns,
  "you vs the plan" per trip. Pro = Google on the scoreboard, all
  history, all destinations, heatmap/trend/race, stops and turns per
  trip, sort/filter, ghost race, drive view, reroute. The Google gate is
  the cost gate: Apple's directions are free, Google's Routes calls are
  not, so free users cost nothing per drive. Locked analytics are shown
  blurred with one button; the paywall counts locked data from the same
  policy that locks it. Prices $3.99 / $24.99, 7-day trial on both,
  family sharing on.
- **D-051**: Terms of Use, liability-first, with Apple's custom-EULA
  clauses (§14) so the same text is the ASC License Agreement. Links
  from `Legal`; onboarding's first Continue records
  `acceptedTermsVersion` (bump `Legal.termsVersion` to ask again).
  Written without legal advice; a lawyer must read it before launch.
- Privacy (D-006) still holds: no accounts, no LawtonCorp server; do
  not add network calls casually. D-017 forces Pro on Brian's personal
  build via `ROUTEWARRIOR_FORCE_PRO=1` in `scripts/signing.local`; he
  comments it out to see the free tier.

## How to work here (environment truths)

- **GitHub Actions is the only compiler** from the cloud session. Local
  gates: `./scripts/kit-purity-gate.sh`, brace/paren balance on every
  edited Swift file, and an adversarial read of the diff. Everything
  else is proven by CI. A brace checker that strips `//` comments will
  also strip `https://` string literals — check the raw text when a URL
  file reports an imbalance.
- Flow: branch `claude/<topic>` from fresh `origin/main` → draft PR →
  when CI is green, mark ready and **squash-merge yourself** → sync
  local main → tell Brian "pull and rebuild" with the exact commands.
  Never merge red, never push to main. GitHub MCP tools: `actions_list`
  (`list_workflow_runs`, `ci.yml`, branch filter, event
  `pull_request`), `get_job_logs` (`failed_only`, tail),
  `update_pull_request` (`draft: false`), `merge_pull_request` (squash,
  `expectedHeadSha`). `subscribe_pr_activity` plus `send_later` (≈9
  min) as the wake timer; never poll. Subscription echoes of your own
  actions (ready-for-review, closed) need no action.
- CI takes 5–9 minutes. Two in-flight PRs that both append to
  `DECISIONS.md` conflict; merge main into the later branch and keep
  both entries in numeric order (happened with #45/#46).
- Commit and PR footers are given by the session harness; never put a
  model identifier in a commit, PR or code comment.
- Secrets: the Google key lives only in gitignored `scripts/signing.local`
  / environment. Never paste it into chat.
- Images: headless Chromium at `/opt/pw-browsers/chromium_headless_shell-*/
  chrome-linux/headless_shell --window-size=1024,1024 --screenshot=…
  file://…svg` renders an SVG to PNG (the full `chrome` binary clips the
  bottom to the viewport). No PIL, no Playwright module. Brian can see a
  rendered file only through `SendUserFile`.

## Scar tissue (bugs the next session should not re-earn)

- **`RoutesProviding` is `Sendable`.** A test stub with a mutable
  counter must be `@MainActor` (a main-actor class satisfies a
  nonisolated async requirement). Capturing a mutable local in a
  `@MainActor` closure: use a small `@MainActor` box class instead.
- **`RouteVariant.representativePolyline` is resampled to 64 points**
  (RouteMatcher, D-023): coarser than a block. Anything geometric per
  route (turns) must come from the trips' own tracks, never that line.
- **The manual Record button never ran the departure prediction** until
  D-045 (`startManualRecording` bypassed `handle(.tripStarted)`); the
  fix fires `beginSnapshotFetch` on the first ingested sample, because
  the buffer is empty at the tap.
- **`ToolbarContentBuilder` and `ViewBuilder` accept `if`/`else`**;
  `switch` over an optional enum uses `case .year?:` and `default:`
  (not `@unknown default`) when the enum may be non-frozen.
- `ForEach(Array((cond ? [] : xs).enumerated()), …)` — the ternary must
  wrap the array, not the enumerated sequence.
- iOS 18 icon appearances: `Contents.json` entries with
  `"appearances": [{"appearance": "luminosity", "value": "dark"|"tinted"}]`
  on the universal 1024 entry compile fine on the CI Xcode.
- `.storekit` v3 intro offer shape:
  `"introductoryOffer": {"internalID": "…", "paymentMode": "free",
  "subscriptionPeriod": "P1W"}`.
- Earlier scars still apply: statics on SwiftUI Views are MainActor
  (`nonisolated static` for helpers/tests), no `let x = x` shadowing in
  closures, `Self` in stored-property initializers, CloudKit
  `ModelContainer` in unsigned CI builds (in-memory under a test host),
  SwiftData+CloudKit model rules, `-allowProvisioningUpdates` not
  registering App Groups/iCloud containers, never `killall
  CoreSimulatorService`, never sign in `project.yml`, never replace a
  file region by slicing from an index.

## What Brian has been asked to do (outside the repo)

1. **Rebuild** with main at #50 and check the free tier (comment out
   `ROUTEWARRIOR_FORCE_PRO=1`, rebuild, put it back): blurred sections,
   locked rows, Trips toolbar → paywall, "Google's plan is part of Pro"
   on the Google map, paywall counts.
2. **App Store Connect subscriptions**: group "Route Rebel Pro", Pro
   Monthly $3.99, Pro Annual $24.99, Introductory Offer *Free / 1 week*
   on each, Family Sharing on; sandbox-test with a fresh tester (a
   tester who has used a trial is not offered another).
3. **Legal**: a lawyer reads `docs/TERMS_OF_USE.md` (confirm Colorado /
   Denver in §13); host both documents (the website sessions below);
   set the privacy URL in ASC App Information and paste the Terms as the
   custom License Agreement.
4. **Website**: Brian has two prompts (given in chat on 2026-09-10) for
   separate sessions — a designer producing a static HTML/CSS prototype,
   then a coder building Next.js on Vercel with DNS on Cloudflare, no
   Supabase for v1. The site must serve `/terms` and `/privacy` from the
   two Markdown files and carry the App Store badge.
5. Google Cloud key restrictions and quotas; CarPlay driving-task
   entitlement request (`docs/HANDOFF.md`); App Privacy questionnaire.

## What's next (the next session's agenda, in Brian's order)

1. **Turn-by-turn directions: can we?** D-034 chose Apple Maps hand-off
   because Apple's CarPlay *navigation* entitlement is granted only to
   turn-by-turn apps and MapKit gives route steps but no guidance
   engine. Re-examine honestly with concrete options and costs:
   (a) in-app guidance on the phone only — `MKRoute.steps` /
   `MKDirections` give instructions, distances and polylines per step;
   we would build the maneuver banner, distance-to-next, off-route
   detection (reuse `OffPlanDetector`) and reroute (`rerouteAvailable`
   is already Pro), with `AVSpeechSynthesizer` for voice; no entitlement
   needed for the phone screen, but CarPlay would still be Apple Maps;
   (b) Google Navigation SDK for iOS — real guidance, but a heavy SDK,
   Google's terms, and per-use billing; (c) keep the hand-off. Whatever
   is chosen, the departure snapshot must not move (D-010) and the
   scoreboard must keep working. Product decision → Brian, with options.
2. **Privacy and Terms inside the app.** Today they are links to
   routerebel.app. Brian wants them "added to the app": bundle the two
   Markdown files as resources (declare in `project.yml`), render them
   in-app (a `LegalDocumentView` from Markdown), keep the links as well,
   and re-ask for acceptance when `Legal.termsVersion` changes (a
   `needsAcceptance` gate at the root, for existing installs). Keep the
   docs in one place: the bundled copies are what the site serves.
3. **App submission info.** Write `docs/APP_STORE_SUBMISSION.md` from
   `docs/APP_STORE_LISTING.md`, `docs/APP_REVIEW_NOTES.md` and
   `docs/HANDOFF.md` §5: name, subtitle, description, keywords,
   category, age rating answers, support URL (routerebel.app/support),
   marketing URL, screenshots list (6.7"/6.1"), review notes and demo
   video, App Privacy answers (from Xcode's Generate Privacy Report),
   export compliance (`ITSAppUsesNonExemptEncryption` NO in
   `project.yml`), the subscription and EULA steps, and the archive /
   upload steps from his Mac. Then walk him through it in order.
4. Field-test findings on the turn counter and the Pro gates, as
   screenshots → small PR → merge on green → "pull and rebuild".

## Working with Brian

Substance over ceremony. He delegates thresholds and technical choices
("merge when green") but decides product questions; ask with concrete
options (AskUserQuestion works well: Record/Go, pricing, website
questions). For anything on his Mac, give exact commands or click
steps. He reads DECISIONS.md — keep writing the "rejected" half. Reports
come as screenshots with a one-line note; read them closely, they often
show a second defect he did not mention. He iterates visually (the icon
took three passes before he supplied his own); show renders with
`SendUserFile` before committing art. When a session fills up, refresh
this file and give him a paste-ready prompt for the next one.
