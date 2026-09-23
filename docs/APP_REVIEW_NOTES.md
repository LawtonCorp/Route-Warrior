# App Review notes — Route Rebel

_Paste into App Store Connect's review notes; attach the demo video._

## What the app does

Route Rebel records the routes a driver actually takes to their frequent
destinations, snapshots Google's planned route and traffic-aware ETA at the
moment of departure, and shows whether the driver's own routes beat
Google's — including stop-sign/signal counts and time-of-day analytics. A
Live Activity shows a live "ghost race" against the driver's personal best
on repeat routes. Once a driver has repeated a journey a few times, their
own routes are offered on the Route tab alongside the providers' plans,
with a recommendation for the current day and time.

## Why Always location (the core of this review)

Hands-free recording is the product: drivers must not interact with a phone
to start a trip. The app arms on automotive motion and records only during
drives; a power-tiering design keeps idle drain at baseline (significant-
change monitoring only, full-rate GPS only while a drive is on).

- The user is educated **before** any permission prompt (onboarding
  explains what is recorded and where it lives), and the app is fully
  functional with While-Using + the manual record button — Always is an
  upgrade the user chooses for hands-free convenience.
- Location history never reaches us: on-device + the user's **private**
  CloudKit database only. No accounts, no ads, no tracking, no analytics
  SDK. The only third-party SDK is Google Maps SDK for iOS, used to draw
  the map when the user picks Google in Settings (Apple is the default).
- The only network calls are route requests to Apple (MapKit) and, for
  Pro, Google at departure, an OpenStreetMap query for intersection data
  (padded box, not the route), and the Google map's own tile loads when
  Google is the chosen map.

## Personal routes need history, so a fresh account will not show them

The store listing describes the driver's own routes appearing on the Plan
tab with a "usually fastest right now" recommendation. **This feature is
built from the account's own recorded drives, so a new install has
nothing to show and the rows are simply absent.** It is not missing or
broken; there is no history yet. We would rather say so here than have
the reviewer look for it.

What it takes for the rows to appear: several recorded drives between the
same two saved places, matched to the same road. Before three drives on
each of two different roads, the app makes no claim at all — and the
sharper claims ("usually fastest on Tuesday mornings") need five drives
in that same weekday and time slot. The feature deliberately stays quiet
rather than guessing from thin data.

The attached demo video therefore shows this feature on a developer
account that has months of real driving history. Everything else in the
video is a fresh install.

The feature is part of the Route Rebel Pro subscription. On the free
tier the Route tab shows a single locked row naming how many of the
driver's own routes were found, which opens the paywall.

## Pausing a drive, and the "Still there?" notification

The recorder has a pause button beside stop. Pausing stops the clock —
the paused time is excluded from the drive's duration, so a stop for fuel
or coffee does not count against the navigation app's ETA — and the map
shows a "Paused" badge while nothing is being recorded. A play button
resumes the same drive.

A paused drive that is left alone raises a **local** notification,
"Still there?", with two actions: *Still here* (keep it paused) and *End
the drive*. If it is not answered, the drive stops itself and **is
saved**, ending at the moment it was paused — nothing recorded is
discarded. The driver sets that limit in Settings → Recording ("Pause
becomes a stop after", twenty minutes by default), and the question
arrives before it.

This is a `UNUserNotificationCenter` local notification, scheduled on the
device by the app itself. Route Rebel has no backend and sends no push
notifications to users; nothing about this question leaves the phone.

## Why background audio

Route Rebel Pro speaks turn-by-turn directions on the drive view. The
`audio` background mode lets those spoken callouts play with the screen
locked or another app in front, through the car's speakers when the
phone is connected. Nothing else plays audio; the mode is used for
nothing else.

## Demo video (attach)

1. Fresh install → onboarding explains recording and privacy → permission
   primers appear in order (While-Using → Always upsell, Motion,
   Notifications).
2. A drive recorded hands-free: app in background, phone locked.
3. Trip detail afterwards: actual route vs. Google's dashed line, ETA
   delta, stop/signal counts.
4. Ghost race Live Activity updating on the lock screen during a repeat
   drive.
5. Pause during a drive: the "Paused" badge over the map, the play button
   where pause was, and the trip afterwards showing the paused time
   listed separately and excluded from the duration.
6. Personal routes on the Route tab — **filmed on a developer account with
   real driving history**, for the reason given above: the driver's own
   roads listed above the providers' plans, each with its usual duration
   and the number of drives behind it, and the top one carrying its
   recommendation for the current day and time.

## Test notes

- No account needed; everything works on first launch.
- Without a Google API key configured the comparison row reads "no
  comparison" — recording and analytics still work (reviewer builds have
  the key baked in).
- Subscription (Route Rebel Pro) gates Google's plan on the scoreboard,
  history depth, analyzed destinations, deep analytics, the ghost race,
  the driver's own routes as departure choices, the drive view with
  turn-by-turn and reroute; recording itself is never gated. Sandbox
  purchase, restore and cancellation work normally; both products carry
  a 7-day free trial.
- Pause and resume are on the recorder row of the Route tab and on the
  drive view. To see the "Still there?" notification without waiting,
  set Settings → Recording → "Pause becomes a stop after" to 5 minutes:
  the question then arrives 3 minutes into a pause, and the drive stops
  itself and saves at 5.
- Two kinds of local notification exist, both scheduled on the device:
  the "Still there?" question above, and a one-tap destination picker
  offered when a drive starts somewhere the app cannot predict. The
  destination one carries the saved places as notification actions, and
  tapping the notification itself opens the same list inside the app.
  Declining notification permission costs neither feature anything that
  blocks recording.
- Terms of Use and Privacy Policy are readable inside the app
  (Settings → About) and linked on the paywall, in onboarding and on the
  web at https://routerebel.app/terms and /privacy.
