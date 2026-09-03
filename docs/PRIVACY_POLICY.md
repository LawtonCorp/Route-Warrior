# Route Rebel Privacy Policy

_Draft — host at a public URL before submission and set the effective date._

Route Rebel is built so that we — LawtonCorp — cannot see your data at
all. There are no accounts, no analytics SDKs, no advertising identifiers,
and no LawtonCorp servers.

## What the app records

When you drive, Route Rebel records your route (GPS track), timing,
detected stops, and derived statistics. This data exists in exactly two
places, both under your control:

- **Your device.**
- **Your private iCloud database**, if iCloud is enabled — Apple's
  CloudKit private database, readable only by your Apple ID. We have no
  access to it.

Deleting the app (and its iCloud data via iOS Settings) removes everything.
"Delete all data" in Settings does the same from inside the app.

## What leaves your device

Two narrowly scoped requests, both essential to features you can see:

1. **Google Routes API** — at departure, the app asks Google for its
   planned route and ETA between your trip's start point and predicted
   destination, so your actual drive can be compared against Google's
   plan. Google receives those coordinates and the request time, governed
   by [Google's privacy policy](https://policies.google.com/privacy). No
   name, email, or identifier of yours accompanies the request.
2. **OpenStreetMap (Overpass API)** — to count stop signs and traffic
   signals, the app requests intersection data for a padded bounding box
   around a route — a deliberately blurred area, not your exact path.
3. **Google Maps SDK** — only when you choose Google as your map in
   Settings (Apple is the default). Google's map software then runs
   inside the app to draw the map, and it talks to Google to fetch map
   imagery and to report usage and diagnostics, as described in
   [Google's privacy policy](https://policies.google.com/privacy). With
   Apple as your map, this component is idle.

That is the complete list. If a future version adds anything to it, this
policy will change and the app will say so.

## What we collect

Nothing. LawtonCorp receives no telemetry, no crash reports beyond what
you opt to share with Apple, and no usage data. The App Store's privacy
label reflects the Google Maps SDK's own disclosures when Google is your
chosen map; it is not data we ever see.

## Permissions the app asks for

- **Location (Always)** — powers hands-free trip recording. You can use
  While-Using or manual recording instead; Always simply removes the taps.
- **Motion & Fitness** — tells the app when a drive starts and ends.
- **Notifications** — trip-saved notices and the destination picker.

## Children

Route Rebel is a driving app and is not directed at children under 13.

## Contact

Questions: brian@lawtoncorp.com
