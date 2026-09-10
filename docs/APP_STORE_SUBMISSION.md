# App Store submission — Route Rebel, in order

_Everything App Store Connect will ask for, with the answers, in the
order it asks. Paste-ready text lives in `docs/APP_STORE_LISTING.md`
(store page) and `docs/APP_REVIEW_NOTES.md` (review notes); this file
says where each goes and what to click. Work top to bottom; later
steps depend on earlier ones. Every command runs from
`/Users/roar/Route-Warrior`._

## 0. Before App Store Connect

| # | Done when | Where |
|---|---|---|
| 0.1 | A lawyer has read `docs/TERMS_OF_USE.md` — §1 (the App gives directions, and what they are worth), §13 (Colorado / Denver) and the liability cap in §9 in particular. | Outside the repo. The effective date at the top of the file is the Terms version the app ships (`LegalTests` holds `Legal.termsVersion` equal to it); a change to the text after launch means a new date, and every install is asked to accept once. |
| 0.2 | `docs/PRIVACY_POLICY.md` has its real effective date. | Top of the file. |
| 0.3 | The website serves both files at https://routerebel.app/terms and https://routerebel.app/privacy, and a support page at https://routerebel.app/support (an email address and a sentence is enough). | Website sessions. The app bundles the same two files; the URLs are what Apple checks. |
| 0.4 | Google Cloud key: **iOS apps** restriction with both bundle ids, API restriction to Routes API + Maps SDK for iOS, a daily quota, a billing alert. | `docs/HANDOFF.md` §2. |
| 0.5 | Apple Developer Program active; **Paid Apps Agreement** accepted with banking and tax forms complete. Subscriptions cannot be created for review without it. | App Store Connect → Business (or Agreements, Tax, and Banking). |
| 0.6 | `project.yml` has the version you mean to ship: `MARKETING_VERSION: "1.0"`, `CURRENT_PROJECT_VERSION: "1"`. Every upload needs a build number higher than the last upload of that version. | `project.yml` (both targets — keep the widget in step). |

## 1. Create the app record

App Store Connect → My Apps → **+** → New App.

| Field | Answer |
|---|---|
| Platforms | iOS |
| Name | `Route Rebel` (must be unique on the store; if taken, `Route Rebel — Beat the Nav`) |
| Primary language | English (U.S.) |
| Bundle ID | `com.lawtoncorp.routewarrior` — appears in the menu once a device build has registered it (`./scripts/device-build.sh` does that through `-allowProvisioningUpdates`). If it is missing, register it at developer.apple.com → Identifiers with the App Groups, iCloud and Push capabilities ticked. |
| SKU | `routewarrior-ios-1` (internal, never shown) |
| User access | Full Access |

## 2. App Information (left column, General)

| Field | Answer |
|---|---|
| Name | Route Rebel |
| Subtitle | Beat the nav. Prove it. |
| Primary category | Navigation |
| Secondary category | Utilities |
| Content rights | **Yes**, the app displays third-party content (Apple and Google map data, OpenStreetMap intersection data), and you have the rights — each is used through its owner's SDK or API under its own terms. |
| Age rating | Open the questionnaire; answer **None** to every content question, **No** to unrestricted web access, gambling and contests. Result: **4+**. |
| License Agreement | **Custom** → paste the whole of `docs/TERMS_OF_USE.md` (the HTML comment at the top is a maintainer note; leave it out). §14 carries the clauses Apple requires in a custom EULA. |
| Privacy Policy URL | `https://routerebel.app/privacy` |
| Privacy Choices URL | leave empty |

## 3. Pricing and Availability

| Field | Answer |
|---|---|
| Price | Free (Pro is the subscription, step 7) |
| Availability | All countries or regions |
| Pre-orders | Off |
| Distribution to Apple Vision Pro / Mac | Untick "Make this app available on Apple Vision Pro" and on Macs with Apple silicon — the app needs a phone in a car. |

## 4. App Privacy (the questionnaire)

Apple's definition of "collected" is *sent off the device to you or a
partner*, and two things are: the coordinates in route requests, and
whatever the Google Maps SDK reports when Google is the chosen map. So
the label is not "Data Not Collected". Answer from the privacy report,
which lists what every bundled SDK declares:

1. Make the archive (step 6, `./scripts/archive.sh`). In the Organizer
   window that opens, right-click the archive → **Generate Privacy
   Report** → Save → open the PDF.
2. App Store Connect → App Privacy → **Get Started** → "Yes, we collect
   data from this app".
3. Tick these data types and answer each the same way unless the PDF
   says otherwise:

| Data type | Used for | Linked to the user? | Used for tracking? | Why |
|---|---|---|---|---|
| Location → Precise Location | App Functionality | No | No | Trip start and destination coordinates go to Apple (MapKit) and, for Pro, Google Routes for the plan; the Google map SDK also reports location when it is the chosen map. |
| Location → Coarse Location | App Functionality | No | No | A padded bounding box goes to OpenStreetMap for stop signs and signals. |
| Identifiers → Device ID | App Functionality | No | No | Only if the privacy report lists it for the Google Maps SDK. |
| Diagnostics → Crash Data, Performance Data, Other Diagnostic Data | App Functionality | No | No | Only if the report lists them for the Google Maps SDK. |

Everything else: **not collected**. Nothing is linked to identity (there
are no accounts) and nothing is used for tracking (`PrivacyInfo.xcprivacy`
declares `NSPrivacyTracking` false). Publish the answers; they can be
changed later without a new build.

## 5. Version 1.0 page

App Store Connect → iOS App → 1.0 Prepare for Submission.

### Screenshots

Six shots, in the order of `docs/APP_STORE_LISTING.md` → Screenshots.
The 6.9" slot is the only required one; it accepts 1320×2868 (iPhone
16 Pro Max) or 1290×2796 (iPhone 15 Pro Max / 16 Plus). Take them on
the phone: **Side button + Volume up**, then AirDrop to the Mac. Pro
should be on (`ROUTEWARRIOR_FORCE_PRO=1` in `scripts/signing.local`,
rebuild) so the analytics are not blurred. The lock-screen ghost race
shot is a screenshot during a real repeat drive — do it as a passenger,
or have someone else drive. Drag the files into the 6.9" slot; the
smaller iPhone slots scale from it. No iPad slot: the app is iPhone-only.

### Text

| Field | Source |
|---|---|
| Promotional text (170) | `docs/APP_STORE_LISTING.md` → Promotional text |
| Description | `docs/APP_STORE_LISTING.md` → Description |
| Keywords (100) | `docs/APP_STORE_LISTING.md` → Keywords |
| Support URL | `https://routerebel.app/support` |
| Marketing URL | `https://routerebel.app` |
| Version | 1.0 |
| Copyright | 2026 LawtonCorp |

### Build

Appears here after step 6. Select it. Because `project.yml` sets
`ITSAppUsesNonExemptEncryption: false`, App Store Connect does not ask
the export-compliance question; if it ever does, the answer is **No** —
the app uses only Apple's standard TLS for its network calls, which is
exempt.

### In-App Purchases and Subscriptions

The first submission of a subscription must ride with a version: in this
section click **+** and add both Pro products (created in step 7). They
are reviewed with the build.

### App Review Information

| Field | Answer |
|---|---|
| Sign-in required | No |
| Contact | Brian Lawton, phone, brian@lawtoncorp.com |
| Notes | Paste `docs/APP_REVIEW_NOTES.md` from "What the app does" to the end. |
| Attachment | The demo video (step 8). |

### Version Release

**Manually release this version** — you press Release after approval,
once the website and the subscriptions are confirmed live. Phased
release: off for 1.0 (nobody to phase to yet).

## 6. Archive and upload from the Mac

`scripts/archive.sh` is `device-build.sh`'s sibling: it regenerates the
project, archives Release signed with the team and Google key from
`scripts/signing.local`, refuses to ship a build with Pro forced on, and
opens the archive in Xcode's Organizer.

```bash
cd /Users/roar/Route-Warrior
git checkout main && git pull
./scripts/archive.sh
```

In the Organizer window: **Distribute App → App Store Connect → Upload
→ Next** on every page (upload symbols on, manage version and build
number off) → **Upload**. Or, without the clicks:

```bash
./scripts/archive.sh --upload
```

Processing takes 10–30 minutes; the build then appears under TestFlight
→ Builds and in the Build section of the version page. Mail from Apple
saying "Missing Compliance" means the encryption key was not read —
check that `ITSAppUsesNonExemptEncryption` is in `project.yml`.

To ship again: bump `CURRENT_PROJECT_VERSION` in `project.yml` (both
targets), commit through a PR, and re-run.

## 7. Subscriptions

App Store Connect → the app → **Subscriptions** (under Monetization or
Features).

1. **Create Subscription Group**: reference name `Route Rebel Pro`. In
   the group's App Store localization: display name `Route Rebel Pro`,
   custom app name leave empty.
2. **Create Subscription** ×2, matching `App/RouteWarrior/RouteWarrior.storekit`
   exactly:

| | Monthly | Annual |
|---|---|---|
| Reference name | Pro Monthly | Pro Annual |
| Product ID | `com.lawtoncorp.routewarrior.pro.monthly` | `com.lawtoncorp.routewarrior.pro.annual` |
| Duration | 1 month | 1 year |
| Price | $3.99 (USD, let Apple set the others) | $24.99 |
| Family Sharing | On | On |
| Introductory Offer | Free, 1 week, all countries, no end date | same |
| Localization (en-US) display name | Pro Monthly | Pro Annual |
| Localization description | Google on the scoreboard, all history, every destination, the ghost race. | Google on the scoreboard, all history, every destination, the ghost race — about $2 a month. |
| Review screenshot | A screenshot of the paywall (Settings → Unlock…); one per product, required | same |
| Review notes | "Pro unlocks the features listed on the paywall; recording is free for everyone." | same |

3. Group level: the annual product is level 1 (the better deal), the
   monthly level 2, so upgrades and downgrades read correctly.
4. **Sandbox**: Users and Access → Sandbox → Testers → add a fresh Apple
   ID. On the phone, Settings → App Store → Sandbox Account → sign in.
   With Pro **not** forced (comment out `ROUTEWARRIOR_FORCE_PRO=1`,
   rebuild), buy Monthly, check the trial line read "7 days free, then
   $3.99 per month" before the tap, restore, cancel in Settings →
   Subscriptions. A tester who has used a trial is not offered another —
   make a new tester to see the line again.
5. Put `ROUTEWARRIOR_FORCE_PRO=1` back for your own daily build.

## 8. The review demo video

Reviewers cannot drive, so the video is the review. Record on the phone
(Settings → Control Center → add Screen Recording; swipe down, tap the
record button; the red status bar marks it) and trim in Photos. One
file, under 500 MB, two to four minutes, in this order:

1. Delete and reinstall, open: onboarding — the three pages, the
   Terms line under the first Continue, the location primer that asks
   While Using and then Always, the Motion prompt. (If Always was
   already granted, Settings → Route Rebel → Location → Never first.)
2. Lock the phone, drive a few minutes (as a passenger): show the phone
   locked, then unlock and show the recorder row "Rec" on the Plan tab.
3. A planned drive: type a destination, both plans appear with ETA and
   turn counts, tap Go, the drive view with the maneuver banner and the
   scoreboard, a spoken callout audible in the recording.
4. Trip detail afterwards: the driven line against the plan's dashed
   line, ETA delta, stops and turns.
5. The lock screen during a repeat drive: the ghost race Live Activity.
6. Settings → About → Terms of Use opens in the app; Settings → Unlock
   → the paywall with the trial lines and the two links.

Attach it under App Review Information. The notes in
`docs/APP_REVIEW_NOTES.md` refer to it by these six steps.

## 9. TestFlight first

Before submitting for review, TestFlight the same build.

1. TestFlight → Internal Testing → create a group, add yourself; the
   build is available within minutes.
2. External Testing → create a group, add 5–20 testers by email; the
   first external build goes through a short beta review (usually a
   day). Test information: use the review notes' first paragraph.
3. Two weeks of real driving across testers. Watch for: drives that did
   not record (Settings → Recorder log tells why), phantom drives,
   battery complaints, turn counts that look wrong, spoken callouts
   that come late or twice.
4. Fix, bump the build number, re-run `./scripts/archive.sh --upload`.

## 10. Submit

Version page → **Add for Review** → **Submit to App Review**. Reviews
take a day or two; the first one for a subscription app more often two.
Likely questions, and the answers already in place:

| Guideline | What they check | Where the answer is |
|---|---|---|
| 5.1.1 (location) | Purpose strings explain Always; the app works without it | `project.yml` purpose strings; onboarding; review notes "Why Always location" |
| 2.5.4 (background modes) | `location` and `audio` are used for what they claim | Review notes "Why background audio"; the video shows the callout |
| 3.1.2 (subscriptions) | Price, duration and trial shown before purchase; Terms and Privacy links | Paywall rows and links; App Information License Agreement |
| 5.1.2 (data use) | Privacy label matches what leaves the phone | Step 4; the Privacy Policy's "What leaves your device" |
| 4.5.x / 2.1 (completeness) | The reviewer can see the features work | The video; sandbox Pro |

If it is rejected, the message names the guideline; reply in Resolution
Center with the fact they missed (most often "see minute 1:40 of the
attached video") before changing anything.

## 11. After approval

1. Confirm https://routerebel.app/terms, /privacy and /support are live.
2. Version page → **Release This Version**.
3. Watch App Store Connect → Analytics for crashes (Xcode → Organizer →
   Crashes shows symbolicated ones from users who opted in).
4. Next version: bump `MARKETING_VERSION` to `1.1` and reset
   `CURRENT_PROJECT_VERSION` to `1` in `project.yml`, land it through a
   PR, and repeat from step 5 with a new version in App Store Connect.
