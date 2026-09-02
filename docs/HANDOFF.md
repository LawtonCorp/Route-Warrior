# Route Warrior — Human handoff checklist

Everything below requires accounts, hardware, or judgment that only Brian
has. The code side of v1 is complete and CI-green without these; each item
says exactly what to do and which milestone's exit criterion it satisfies.
Work top to bottom — later items depend on earlier ones.

## 1. Apple Developer / App Store Connect (needed before any device work)

1. Ensure the LawtonCorp Apple Developer Program membership is active.
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

1. In App Store Connect create the subscription group "Route Warrior Pro"
   and two auto-renewable products matching
   `App/RouteWarrior/RouteWarrior.storekit` exactly:
   `com.lawtoncorp.routewarrior.pro.monthly` and
   `com.lawtoncorp.routewarrior.pro.annual`, with your chosen prices
   (the .storekit placeholders are $2.99 / $19.99).
2. Sandbox-test purchase, restore, and cancellation on-device.
3. **Your own Pro unlock (D-017)**: add `ROUTEWARRIOR_FORCE_PRO=1` to
   `scripts/signing.local` and re-run `./scripts/device-build.sh` — your
   builds report Pro without a subscription. Comment it out when you want
   to test the real purchase/sandbox flow on your phone; it never affects
   CI or App Store archives (the setting is empty unless this script
   passes it).

## 5. App Store submission (M6)

1. Host the privacy policy (docs/PRIVACY_POLICY.md) at a public URL and set
   it in App Store Connect.
2. App Privacy questionnaire: since the Google map (M8) the app links
   the Google Maps SDK, which declares its own collection, so "Data Not
   Collected" no longer applies. Do this once from the archive: Xcode →
   Product → Archive → in the Organizer, right-click the archive →
   **Generate Privacy Report** → open the PDF; it lists every data type
   the bundled SDKs declare. Answer the App Store Connect questionnaire
   from that PDF, mark each Google type as "not linked to the user" and
   "not used for tracking" unless the report says otherwise, and attach
   nothing for LawtonCorp itself — we still collect nothing.
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
