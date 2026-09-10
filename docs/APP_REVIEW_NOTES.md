# App Review notes — Route Rebel

_Paste into App Store Connect's review notes; attach the demo video._

## What the app does

Route Rebel records the routes a driver actually takes to their frequent
destinations, snapshots Google's planned route and traffic-aware ETA at the
moment of departure, and shows whether the driver's own routes beat
Google's — including stop-sign/signal counts and time-of-day analytics. A
Live Activity shows a live "ghost race" against the driver's personal best
on repeat routes.

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

## Test notes

- No account needed; everything works on first launch.
- Without a Google API key configured the comparison row reads "no
  comparison" — recording and analytics still work (reviewer builds have
  the key baked in).
- Subscription (Route Rebel Pro) gates Google's plan on the scoreboard,
  history depth, analyzed destinations, deep analytics, the ghost race,
  the drive view with turn-by-turn and reroute; recording itself is never
  gated. Sandbox purchase, restore and cancellation work normally; both
  products carry a 7-day free trial.
- Terms of Use and Privacy Policy are readable inside the app
  (Settings → About) and linked on the paywall, in onboarding and on the
  web at https://routerebel.app/terms and /privacy.
