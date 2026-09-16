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
   (`group.com.lawtoncorp.routewarrior`), and the iCloud container
   (`iCloud.com.lawtoncorp.routewarrior`) automatically.
   **M0 exit criterion: the app icon appears on your phone.**

## 2. Google Cloud — Routes API key (M3's comparison feature)

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

### Field tests this session's work still needs (phone in hand)

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
  button where pause was, and Stop still reachable — on the Plan tab's
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
- **D-071, the ladder**: CI proves the rungs behave as written; only
  Brian's own history says whether they are the right rungs. The number
  to watch is how often a recommendation actually lands at tier 1
  ("usually fastest on Tuesday mornings") rather than widening — five
  drives in one weekday-and-slot cell is a lot to ask, and if it never
  happens the sharpest sentence the feature can say is one it never
  says.
