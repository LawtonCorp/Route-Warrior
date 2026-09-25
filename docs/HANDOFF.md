# Route Rebel — Human handoff checklist

Everything below requires accounts, hardware, or judgment that only Brian
has. The code side of v1 is complete and CI-green without these; each item
says exactly what to do and which milestone's exit criterion it satisfies.
Work top to bottom — later items depend on earlier ones.

## 1. Apple Developer / App Store Connect (needed before any device work)

1. Ensure the Lawton, LLC Apple Developer Program membership is active.
2. In Xcode → Settings → Accounts, sign in; note the Team ID.
3. `echo 'ROUTEWARRIOR_TEAM=YOURTEAMID' > scripts/signing.local` (gitignored).
4. First device build: `./scripts/device-build.sh` — `-allowProvisioningUpdates`
   registers the bundle IDs (`com.lawtoncorp.routewarrior`,
   `.routewarrior.widgets`), the App Group
   (`group.com.lawtoncorp.routerebel`), and the iCloud container
   (`iCloud.com.lawtoncorp.routewarrior`) automatically.
   **M0 exit criterion: the app icon appears on your phone.**

## 2. Google Cloud — Routes API key (M3's comparison feature)

**Status 2026-09-23: done**, except API restrictions (step 3's second
half), which is deliberately parked; the actual configuration — 1,000
requests a day rather than the 2,000 below, the matrix method closed —
is in the 2026-09-16 → 23 session log. The steps below are kept as the
record of how the key was set up.

1. Create a Google Cloud project (e.g. `route-warrior-prod`) with billing.
2. Enable **Routes API**.
3. Create an API key; under *Application restrictions* choose **iOS apps**
   and add both bundle IDs; under *API restrictions* limit to Routes API.
4. Set a daily quota cap (start: 2,000 requests/day) and a billing alert.
5. Verify current pricing/SKU for `computeRoutes` with `TRAFFIC_AWARE` —
   the cost model assumes ~2 calls/trip, ~250/heavy user/month.
6. Provide the key at build time (never commit it):
   `ROUTEWARRIOR_ROUTES_KEY=xxx ./scripts/device-build.sh` — it lands in
   Info.plist as `GoogleRoutesAPIKey`. Keyless builds run fine; trips just
   show "no comparison".
7. **For the Google map (M8)**: enable **Maps SDK for iOS** on the same
   project (APIs & Services → Library) and add it to the key's *API
   restrictions* next to Routes API. Map loads are free and unlimited;
   set a daily quota anyway (Google Maps Platform → Quotas → Maps SDK for
   iOS). Without this the Google map renders blank while everything else
   works.

## 3. Field tests (the phone-in-hand exit criteria)

- **M2 — recording**: carry the app for a week of normal driving. Pass =
  every real drive appears (no missed trips), no phantom trips, battery
  drain acceptable to you. When a drive goes missing, open Settings →
  Recorder log: it says when the app armed, started, and why each
  recording ended, with the point counts the discard thresholds saw.
  Auto-detect thresholds are in `TripRecorder.Config`; tune there if
  reality disagrees, and record the change in DECISIONS.md.
- **M3 — comparisons**: on your known routes, check the trip detail's
  Google-vs-actual delta feels right, and count the actual stop signs and
  signals once to compare against the app's counts (expect OSM gaps —
  that's what the coverage-confidence label is for). Also try a drive the
  predictor can't call (somewhere new): the "Where are you headed?"
  notification should offer your saved places, and one tap should produce
  the comparison.
- **M4 — ghost race**: drive a repeat route with the phone locked; the
  lock-screen delta should update through the drive without opening the app.
- **CloudKit sync**: install on a second device with the same Apple ID;
  trips recorded on one should appear on the other within minutes.

## 4. StoreKit / monetization (M5)

1. In App Store Connect create the subscription group "Route Rebel Pro"
   and two auto-renewable products matching
   `App/RouteWarrior/RouteWarrior.storekit` exactly:
   `com.lawtoncorp.routewarrior.pro.monthly` at **$3.99/month** and
   `com.lawtoncorp.routewarrior.pro.annual` at **$24.99/year** (D-050).
   On each product add an **Introductory Offer**: type *Free*, duration
   *1 week*, all countries, no end date. The paywall reads the offer from
   StoreKit and writes "7 days free, then $24.99 per year" by itself;
   nothing in the app hard-codes a price. Turn Family Sharing on for
   both.
2. Sandbox-test purchase, restore, and cancellation on-device, and check
   that the trial appears on the paywall rows (a sandbox account that has
   already used a trial will not be offered one again — make a fresh
   sandbox tester if the line is missing).
3. **Your own Pro unlock (D-017)**: add `ROUTEWARRIOR_FORCE_PRO=1` to
   `scripts/signing.local` and re-run `./scripts/device-build.sh` — your
   builds report Pro without a subscription. Comment it out when you want
   to test the real purchase/sandbox flow on your phone; it never affects
   CI or App Store archives (the setting is empty unless this script
   passes it).

## 5. App Store submission (M6)

1. Host the privacy policy (docs/PRIVACY_POLICY.md) **and the Terms of
   Use (docs/TERMS_OF_USE.md)** at public URLs, and make them match the
   two constants in `App/RouteWarrior/Support/Legal.swift`
   (`https://routerebel.app/terms` and `https://routerebel.app/privacy`,
   served by the marketing site — change the constants if you host
   elsewhere). Apple's guideline 3.1.2 requires
   working links to both inside an app that sells subscriptions; the app
   shows them in Settings → About, on the paywall, and under onboarding's
   first Continue. In App Store Connect set the privacy URL in App
   Information, and paste the Terms into **App Information → License
   Agreement → Custom** (it includes the Apple clauses a custom EULA must
   carry, §14). The lawyer's read is done: approved as written on
   2026-09-15, so the text goes across unchanged.
2. App Privacy questionnaire: since the Google map (M8) the app links
   the Google Maps SDK, which declares its own collection, so "Data Not
   Collected" no longer applies. Do this once from the archive: Xcode →
   Product → Archive → in the Organizer, right-click the archive →
   **Generate Privacy Report** → open the PDF; it lists every data type
   the bundled SDKs declare. Answer the App Store Connect questionnaire
   from that PDF, mark each Google type as "not linked to the user" and
   "not used for tracking" unless the report says otherwise, and attach
   nothing for Lawton, LLC itself — we still collect nothing.
3. Record the App Review demo video (see docs/APP_REVIEW_NOTES.md) showing
   the always-location education flow and the recording feature.
4. Screenshots (6.7" and 6.1"): Home recording state, Trip detail with
   both polylines, Destination analytics, Ghost race lock screen.
5. TestFlight external beta, 2+ weeks: watch for auto-detect misses and
   battery complaints; then submit with the review notes attached.

## Known limitations shipped in v1 (documented, not bugs)

- No automatic passenger detection — riders use "exclude from stats".
- Stop-sign counts inherit OSM coverage gaps (the confidence label says so).
- Destination prediction is cold for a new user until history accrues.

## CarPlay scoreboard — requesting the entitlement

The scoreboard's numbers and wording ship today and show on the drive
banner. Putting them on the car screen needs an entitlement Apple grants
by application, and nothing in the app can be enabled until it arrives.

1. Go to **developer.apple.com/contact/carplay/**.
2. Choose the app (Route Rebel, bundle id `com.lawtoncorp.routewarrior`).
3. For the app type, choose **Driving task** — *not* Navigation. Driving
   task is for apps that do one focused thing while driving, which is
   what a live scoreboard is; Navigation is for turn-by-turn apps and
   would be declined.
4. Describe it as: a read-only display of how the current drive compares
   with the navigation ETA the driver departed with — a few rows of text,
   updated as the drive progresses, no interaction required.
5. Submit and wait. Apple's review takes weeks and can ask questions.

When it is granted, the remaining work is small and is one pull request:
add `com.apple.developer.carplay-driving-task` to the app's entitlements
in `project.yml`, add the CarPlay scene to the scene manifest, and wire a
`CPTemplateApplicationSceneDelegate` that renders
`ScoreboardText.rows(_:provider:)` into a `CPInformationTemplate`.

**Do not add the entitlement before approval.** `scripts/device-build.sh`
signs with `-allowProvisioningUpdates`, and Apple refuses to issue a
profile carrying an entitlement the account has not been granted — the
build to your phone would start failing.

## Session log — 2026-09-15/16

Ten PRs, all green first time, all squash-merged to main.

| PR | Decision | SHA | What |
|---|---|---|---|
| #62 | D-060 | `8591a93` | A drive can be named; Go defaults to Route Rebel |
| #63 | D-061 | `5d28de7` | What Go does moved under the button, behind a tap |
| #64 | D-062 | `56acaff` | Go defaults to Google Maps where Google Maps exists |
| #65 | D-063 | `5ccc14b` | The route list stays put when you pick a route |
| #66 | — | `48fb296` | The Terms are lawyer-approved as written (docs) |
| #67 | D-064 | `35962fc` | The contracting party is Lawton, LLC |
| #68 | — | `6e1f103` | Spec: personal routes as departure choices |
| #69 | D-065 | `ff4bf22` | RouteRecommender: which of my routes to take now |
| #70 | D-066 | `3626a11` | Your own routes on the Plan tab |
| #71 | D-067 | `798f5de` | The verdict names the road |

### The feature that landed: personal routes (D-065/066/067)

Brian's decisions, 2026-09-16: **Pro** (whole feature, insight included),
**offer not pre-select**, **five drives per route at every tier**, and
**in v1.0** — over the recommendation to ship 1.0 first because the
feature is invisible on a fresh install. `docs/SPEC_PERSONAL_ROUTES.md`
§9 carries the consequences: the review video shows it on Brian's own
history, and the listing should describe it as something the app grows
into.

- `RouteRecommender` (kit, pure) runs `RouteRaceEngine` over four
  narrowing subsets — this weekday+slot, weekday/weekend+slot, this
  slot, everything — and returns the first tier yielding a winner **or a
  tie**. A tie at "Tuesday mornings" is a finding, not a reason to look
  at Wednesdays. The answering tier is named in every claim.
- `PersonalRoutes.rows` turns variants into Plan-tab rows. The number is
  the median at the answering tier when that tier counted the route, the
  all-time median otherwise, always with the drive count.
- **The baseline never moves (D-010).** The provider snapshot is still
  fetched, stored and compared. A personal pick promotes nothing.
- Picking your own route: line drawn beside the provider's, off-route
  watched against *your* line, **no guide object created at all**, and
  the maps-app hand-off skipped — no maps app knows this road.
- `TripRecord.chosenVariantID` holds the pick, apart from `variantID`
  (the matcher's answer). They can disagree; `VerdictText.road` shows
  both rather than choosing.
- Slice 4 (pre-selection) is deliberately **not built**.

### Other decisions this session

- **D-061**: the Go explanation is disclosed behind a tap. The line has
  two faces — "Drive detected…" when armed, "What happens when you tap
  Go" otherwise — because the chip only exists once motion says
  automotive, and the explanation must be reachable from a parked car.
  The D-044 loading sentence stays visible: it is about now.
- **D-062**: Google Maps is the default hand-off **only where the app is
  installed**. Our link is a universal link; without the app it opens
  Safari, which is useless at the wheel and is what a reviewer would
  hit. Detection is `canOpenURL("comgooglemaps://")`, which needs
  `comgooglemaps` in `LSApplicationQueriesSchemes` (project.yml), read
  once at launch.
- **D-063**: tapping an alternate used to rewrite the stored plans, so a
  second tap promoted a promotion and there was no way back to the
  provider's own route. The pick is now a `PlanList.RowID`.
- **D-064**: the contracting party is **Lawton, LLC**. Both legal
  documents are effective **15 September 2026** and
  `Legal.termsVersion = "2026-09-15"` — done pre-launch, when the
  re-acceptance prompt costs one tap. Left alone: the bundle id and its
  containers (identifiers, not names), `brian@lawtoncorp.com`, the
  GitHub org, and D-001's entry in DECISIONS.md.

### Confirmed facts worth not re-deriving

- **Apple Maps always shows its own route preview.** There is no launch
  option to start guidance directly; `openInMaps(launchOptions:)` with
  the driving key lands on the preview every time. Google's
  `dir_action=navigate` does start immediately. The double-Go is
  Apple's, not ours.
- **CarPlay navigation entitlement**: request at
  developer.apple.com/contact/carplay/ as Account Holder; key is
  `com.apple.developer.carplay-maps`. Unverified and worth asking Apple:
  whether holding it forecloses the *driving-task* entitlement this
  repo's §"CarPlay scoreboard" plans. Do not add either to project.yml
  before it is granted.
- **Two settings both say "Google"** and this confused the app's own
  author: "Map & routes" is the embedded SDK and route provider;
  "Navigate with" is the hand-off to the separate app. Relabelling was
  offered and not yet decided.

### App Store, step 0 as it stands

| | Status |
|---|---|
| 0.1 Lawyer review | Done, with one caveat: approval was given for text naming "LawtonCorp"; the party was corrected to Lawton, LLC the same day. One line back from the lawyer is wanted. |
| 0.2 Privacy Policy date | Done — now 15 September 2026, moved with the rename (supersedes the 10 September confirmation, because the text changed). |
| 0.3 Website /terms /privacy /support | Done (confirm live before pressing Release). |
| 0.4 Google Cloud key restrictions | Brian's, in progress. |
| 0.5 Paid Apps → tax → banking | Open. Account Holder only; each step unlocks the next; done when Paid Apps reads **Active**. |
| 0.5a Small Business Program | Open. Needs 0.5 signed first. 15% not retroactive — starts 15 days after the fiscal month-end of approval, so enrol before there are subscribers. |

**Lawton, LLC** must match character for character across the W-9, the
bank account holder and IRS records. Apple cross-checks them.

### Open questions carried forward

- ~~The recommender's floor~~ — settled 2026-09-16 as **D-071**: the
  **3/4/5 ladder**, five at tier 1, four at tier 2, three at tiers 3–4.
  (D-070's flat four stood for about an hour; the ladder is what ships.)
  Narrower claims earn a higher floor, and the widest tier matches
  `RouteRaceEngine`'s three, so the Plan tab and the Destination screen
  no longer disagree about when there is enough history.
- ~~Whether to relabel "Map & routes" and "Navigate with"~~ — settled
  2026-09-16 as **D-068**: the two settings keep their labels and move
  into separate sections, "In Route Rebel" and "When you tap Go".

## Session log — 2026-09-16 → 2026-09-23

Eighteen PRs, all squash-merged to main green. Two went red in CI first
and were fixed before merge (see "Lessons" below).

| PR | Decision | SHA | What |
|---|---|---|---|
| #73 | — | `4f91be9` | Listing: the app sells the routes it learned (docs) |
| #74 | D-068 | `cf0f0dd` | Two settings said "Google"; the headers now say which |
| #75 | D-069 | `39d19f0` | Pause stops the clock |
| #76 | D-070 | `940edb6` | The recommender's floor is four, still flat |
| #77 | D-071 | `2c62b66` | The floor is the 3/4/5 ladder after all |
| #78 | D-072 | `aa11a5c` | A pause that goes quiet is asked about, then stopped |
| #79 | — | `8ce4d95` | Review notes: personal routes and pause (docs) |
| #80 | D-073 | `a650a11` | An alternate is named for whoever proposed it |
| #81 | D-074 | `851678e` | The driver arranges their own places |
| #82 | D-075 | `29f1b92` | A route says where it started |
| #83 | D-076 | `048b923` | The Destination screen answers for one starting point |
| #84 | D-077 | `ece7236` | A screen reads columns; only what it shows gets decoded |
| #85 | D-078 | `06e9a9d` | Start listening at launch, not at the first window |
| #86 | D-079 | `edb1996` | The first tab is Route, not Plan |
| #87 | D-080 | `5dc4c48` | Leave the screen, then delete the drive |
| #88 | — | `eb365a2` | Field tests: D-077 and D-080 confirmed (docs) |
| #89 | D-081 | `8656600` | The driver's answer names the drive |
| #90 | D-082 | `d166683` | Tapping the question asks it again, on a screen |

### What changed, grouped by what the driver sees

- **Recording.** A pause button beside Stop, with a play button and a
  "Paused" map overlay while paused; paused time is excluded from the
  drive's duration and from every comparison (D-069). A paused drive asks
  "Still there?" at twelve minutes and stops itself — saved, ending where
  it paused — at a limit set in Settings, default twenty (D-072).
- **The bug that lost three drives (D-078).** Motion detection was only
  ever started from a `.task` on the root view. A background relaunch —
  how iOS records a drive when the app is not open — builds no window,
  so that task never ran and nothing armed. An `AppDelegate` now starts
  listening at launch, however the launch happened. Old defect (since
  M8), found now only because Brian stopped opening the app before
  driving. **Confirmed on the phone.**
- **Naming drives (D-081, D-082).** The departure notification's answer
  used to buy a plan and nothing else; now it names the stored drive.
  Endpoints are forgiving: inside a place's fence wins, else the nearest
  place within 200 m, else the destination the driver named if the drive
  ended within 500 m of it — where the drive ended always outranks what
  was said. Tapping the notification (rather than pulling it down) now
  opens a picker with every saved place; it used to do nothing at all.
- **Routes and places.** The recommender's floor is a ladder — five
  drives at the narrowest tier, four, then three (D-070 → D-071).
  Alternates are named "Google Alt 1" rather than "Alternate 1" (D-073).
  Places reorder by drag, and the order is what the free tier's
  allowance counts (D-074). Route rows say where they started (D-075),
  and a destination driven to from several places is scoped to one
  starting point at a time, because pooling them produced a fastest
  route that meant nothing (D-076).
- **Speed and stability.** D-076 made the Destination screen decode
  every drive's track a dozen times per render; D-077 answers from stored
  columns and decodes once, and fixed the same shape of waste in the
  Trips list and the rename screen. **Confirmed on the phone.** Deleting
  a drive from its own screen crashed, because the screen read the record
  it had just deleted; it now leaves first and deletes on the way out
  (D-080). **Confirmed on the phone.**
- **Words.** Settings sections "In Route Rebel" and "When you tap Go"
  separate the two Googles (D-068). The first tab is **Route**, not Plan
  (D-079) — and the store docs followed in the PR that wrote this log.

### Brian's product calls this session

- Recommender floor: the 3/4/5 ladder (after one hour of a flat four).
- Pause: "Still there?" at twelve minutes; pauses become a stop after a
  Settings value, default twenty minutes.
- "Alternate 1/2" → "Google Alt 1/2".
- "Plan" tab → "Route".
- **Go with a specific route picked: leave as is.** Tapping Go hands off
  to Google Maps, which re-plans and offers its own three routes again.
  No maps app accepts "drive alternate 2" — the parameter does not exist
  — so the only way to drive the route picked in Route Rebel is Route
  Rebel's own guidance. Offered (guide any specific pick in-app; hand off
  only when the pick matches Google's own choice; ask at Go) and
  declined. The pick still sets the drive's baseline (D-063).
- Tapping the departure notification opens the destination picker.

### Lessons worth keeping

- **The recurring defect this session was a missing case**, not a wrong
  line: D-072's second notification delegate would have silently stolen
  the first's replies, D-078's launch hook never ran for the launch that
  mattered, and D-082's tap fell off the end of an `if`. Nothing was
  wrong on the line being read. Each fix made the cases explicit and
  tested — one delegate, an order-independent launch coordinator, an
  exhaustive `PromptResponse` switch.
- **Two red CI runs.** #83 committed conflict markers after a two-file
  merge conflict was resolved in one file: after any merge, grep the
  whole tree for conflict markers and re-read the merge diff. #84 used
  `RouteVariant` in a file that did not import the kit: check the import
  list of every file that names a new type.
- **Fetch before branching.** #81 branched from a stale `origin/main` and
  conflicted in `DECISIONS.md`.
- **"It used to work" was true and misleading at once.** The background
  launch path had never worked; it only stopped mattering when the app
  happened to be warm. The recorder log settled it in one screenshot —
  an hour of silence with no "Armed" line — and ruled out three theories
  that reading the code had produced.

### Confirmed facts worth not re-deriving

- **No maps app can be told which of its routes to drive.** Google's Maps
  URL contract carries destination, travel mode and `dir_action=navigate`;
  there is no alternate-route parameter. Apple has none either.
- **The app calls exactly one Google endpoint**: Routes API
  `computeRoutes`. It never calls `computeRouteMatrix`. Maps SDK for iOS
  map loads are free and unlimited.
- **The Routes client sends `X-Ios-Bundle-Identifier`**, which is what
  lets an iOS-apps key restriction work for a web-service API. Without
  it every Google plan would 403 once the key was restricted.
- **A background relaunch has no window.** Anything that must run on
  every launch belongs in the app delegate, not a view's `.task`. A
  force-quit from the app switcher stops iOS relaunching the app at all
  until it is opened by hand.
- **Idle location updates now log** at most once per ten minutes, so a
  silent hour in the recorder log means the app was not running.
- **Deleting a SwiftData model under a mounted view traps** — it is not a
  nil and not a thrown error. Leave the screen, then delete.
- **Unverified, worth noticing once:** tapping Go with *no* specific row
  picked should start Google's turn-by-turn immediately
  (`dir_action=navigate`, no origin). If it shows a route preview
  instead, that is a real bug on our side — the likely fix is passing the
  current position as the origin.

### Google Cloud key (checklist 0.4), as it stands

| | Status |
|---|---|
| Application restriction: iOS apps, both bundle ids | Done |
| API restrictions (Routes + Maps SDK for iOS) | **Parked.** The console's key page did not offer the section; not worth fighting given the caps below. The CLI route (`gcloud services api-keys update … --allowed-bundle-ids … --api-target …`, both flags in one call) remains available. |
| `computeRoutes` per-day quota | Done — 1,000/day; email alert at 80%, auto-close one day |
| `computeRouteMatrix` per-day quota | Done — lowered from Unlimited to its minimum; the app never calls it |
| Billing budget | Done |
| Phone check afterwards | Done 2026-09-23 — Google's plan still appears |

### App Store checklist, step 0, as of 2026-09-23

| | Status |
|---|---|
| 0.1 Lawyer review | Done; one line back from the lawyer confirming the Lawton, LLC rename is still wanted. |
| 0.2 Privacy Policy date | Done. |
| 0.3 Website /terms /privacy /support | Done — confirm live before pressing Release. |
| 0.4 Google Cloud key | Done, API restrictions parked (above). |
| 0.5 Paid Apps → tax → banking | **Open, and the next thing to start.** Account Holder only; each unlocks the next; bank verification takes days. The Pro subscriptions cannot be created until Paid Apps reads **Active**. |
| 0.5a Small Business Program | Open. Needs 0.5 first. Not retroactive — enrol before there are subscribers. |
| 0.6 Version numbers | Set: `1.0` / build `1`, both targets. |

### The path to the store from here, in order

1. **0.5** — the agreement chain. Longest lead time; start first.
2. **0.5a** — Small Business Program, as soon as Paid Apps is Active.
3. **0.1** — the lawyer's one line on the renamed party.
4. **§1–3** — the app record, App Information, Pricing and Availability.
5. **§6** — `./scripts/archive.sh --upload`; then **§4**, the privacy
   questionnaire, answered from the archive's privacy report.
6. **§7** — the two Pro subscriptions (blocked on 0.5).
7. **§5 and §8** — seven screenshots and the review demo video. Both
   need the phone, Pro forced on for the screenshots, and someone else
   driving for the lock-screen ghost race and the drive footage.
8. **§9** — TestFlight: internal, then external, two weeks of driving.
9. **§10** — submit; **§11** — release manually after approval.

Before external TestFlight, the open field tests below should be seen at
least once — especially **D-081/D-082**, the two notification paths, and
**D-072**'s "Still there?" answered from the lock screen, since those are
the flows a tester meets without being told.

### Field tests — confirmed, and still open (phone in hand)

- **D-068**: read the two new section headers on the Settings screen and
  say whether "In Route Rebel" / "When you tap Go" actually separates the
  two Googles. CI can only prove the footers no longer explain each
  other's settings.
- **D-069, battery**: the GPS stays on while a drive is paused, on
  purpose (the thing that restarts it only runs off an arriving sample).
  A long pause — an hour at a restaurant — is the case to watch. If the
  drain is bad, the fix is a way to restart location from the play
  button rather than from the sample stream.
- **D-069, the numbers**: pause mid-drive, stop for a few minutes, resume
  and finish. Check the trip detail: Duration should exclude the pause,
  a "Paused" row should show it, and the delta against the nav's plan
  should be what it would have been without the stop. The recorder log
  says how long was excluded.
- **D-069, the screen**: "Paused" over the map on both surfaces, the play
  button where pause was, and Stop still reachable — on the Route tab's
  recorder row and on the drive view.
- **D-072, the pause timeout**: pause a drive and leave the phone alone.
  At twelve minutes "Still there?" should arrive — as an alert if the app
  is open, as a notification with "Still here" / "End the drive" if it is
  not. Tap "Still here" and the drive should survive past twenty minutes;
  ignore it and the drive should stop itself at twenty and be *saved*,
  ending where you paused. The notification half is the part CI cannot
  see at all: check that answering it from the lock screen works, and
  that a destination-pick notification still works afterwards — both
  prompts now share one delegate.
- **D-075/076, one destination, several starting points**: open a
  destination you drive to from more than one place. The picker should
  appear, default to the place you drive from most, and everything below
  it — totals, routes, heatmap, trend — should change when you switch.
  On "All starting points" the head-to-head should be replaced by the
  reason it is missing, and each route row should say where it began.
  The number to sanity-check is the heatmap: the cell that looked wrong
  (Brian's 61-minute Saturday) should look right once scoped, because it
  was one long drive from far away pooled with short ones.
- **D-074, dragging places**: tap Edit on the Places tab and drag a place
  to the top. It should stay there after a relaunch, the Route tab's saved
  places should show the same order, and — on the free tier — the lock
  icons should move with the rows, because the allowance counts positions.
  The half CI cannot see is CloudKit: arrange the list on one phone and
  check the second one follows.
- **D-071, the ladder**: CI proves the rungs behave as written; only
  Brian's own history says whether they are the right rungs. The number
  to watch is how often a recommendation actually lands at tier 1
  ("usually fastest on Tuesday mornings") rather than widening — five
  drives in one weekday-and-slot cell is a lot to ask, and if it never
  happens the sharpest sentence the feature can say is one it never
  says.
- ~~**D-077, the latency**~~ — **confirmed on the phone 2026-09-17**, all
  three screens Brian named: renaming a route ("smooth now"), opening a
  destination from Places, and filtering the Trips list by departure
  ("both feel fine now"). Worth keeping the shape of the finding: CI only
  ever proved that the cheap paths answer the same as the ones they
  replaced. That the screens got *faster* was read off the call graph and
  is now confirmed by a driver, not by a benchmark — nothing here is
  timed, and if the history grows by an order of magnitude this is the
  first place to look again.
- ~~**D-078, the launch that matters**~~ — **confirmed on the phone
  2026-09-18**: "the app is, in fact, starting whenever I drive (even
  when it's closed)". This is the one that cost three drives, and the one
  CI could say nothing about — no test here mounts a background relaunch.
  If drives ever go missing again, the recorder log now distinguishes the
  two cases it could not before: "App launched (woken by a location
  change)" means iOS woke us, and silence through a moving hour means it
  did not.
- **D-083, the paused row**: pause a drive and look at the Route tab's
  recorder row. It should read "Paused" on one line, with a map-icon
  button (no title), play and Stop, and nothing wrapped or cut off.
  Resume, and the button should say "Drive view" again. CI proves the
  words and which state drops the title. Whether it all fits on the
  phone needs someone to look.
- **D-081, the destination the driver names**: drive somewhere the
  predictor cannot call, and when the notification asks, pull it down and
  tap one of the places. The stored drive should carry that destination —
  it should appear on the Destination screen and count toward that
  place's history, not just fetch a plan. Two more worth watching now
  that endpoints are forgiving to 200 m: drives that used to finish with
  no origin (parked outside the fence) should start naming where they
  began, and no drive should be filed under a place it merely parked
  near. The tolerances (200 m, 500 m) are judgement, not measurement — a
  drive filed under the wrong place is the signal they are too wide.
- ~~**D-080, deleting a drive**~~ — **confirmed on the phone 2026-09-17**:
  deleting a drive from its own screen closes cleanly and no longer
  crashes. Two parts of that test have *not* been reported back and are
  still worth a glance next time a drive is deleted: that the route it
  belonged to shows one fewer drive, and that deleting a route's last
  drive removes the route from the destination screen. CI covers both
  against an in-memory store; neither has been seen on a phone.
- **D-082, tapping the departure notification**: start a drive somewhere
  the app cannot predict, and when the notification arrives **tap it**
  rather than pulling it down. The app should open on the destination
  picker with every saved place; picking one should name the drive the
  same way a notification action does, and the sheet should close. Then
  the awkward cases: tap it, hit "Not now", and the drive should carry on
  unnamed; tap it after the drive has already finished, and nothing
  should open (Settings → Recorder log will say the notification was
  tapped after the drive ended). Worth trying once from the lock screen
  and once with the app already open — those are different paths through
  iOS and only the phone runs either.
