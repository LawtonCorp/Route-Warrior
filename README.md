# Route Warrior

An iPhone app for drivers who think they know better than Google Maps — and
want the data to prove it. Route Warrior auto-records the route you actually
drove, snapshots Google's planned route and traffic-aware ETA at the moment
you departed, and turns your history into answers: how long trips really
take, how many stop signs and signals you hit, how traffic compared to
Google's assumption, and whether your route beats Google's — by time of day
and day of week. A live "ghost race" on the lock screen scores a repeat drive
against your personal best.

Product definition lives in [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md)
and [`docs/SPEC.md`](docs/SPEC.md); the milestone plan is
[`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md); every behaviour decision is
recorded in [`DECISIONS.md`](DECISIONS.md). The repo is built on the
LawtonCorp `ios-starter` template, and its working rules are in
[`CLAUDE.md`](CLAUDE.md).

## Layout

```
project.yml                XcodeGen definition; the .xcodeproj is generated, not committed
Package.swift              RouteWarriorKit (UI-free core) + RouteWarriorStore (persistence)
Sources/RouteWarriorKit/   all app logic, testable with plain `swift test`
Sources/RouteWarriorStore/ SwiftData + CloudKit layer (no UI, no algorithms)
Tests/RouteWarriorKitTests/  kit tests (Swift Testing)
App/RouteWarrior/          thin SwiftUI app over the kit
App/RouteWarriorWidgets/   widget extension (ghost-race Live Activity)
App/RouteWarriorTests/     app-target tests — wiring, not logic
scripts/bootstrap.sh       clone → openable Xcode project
scripts/device-build.sh    clone → app installed on your iPhone, one command
scripts/kit-purity-gate.sh CI gate: no UI/CoreLocation/SwiftData imports in the kit
scripts/coverage-gate.sh   CI gate: kit line coverage ≥ 90%
.github/workflows/ci.yml   three jobs: Linux gates, kit tests, simulator app build
docs/                      requirements, spec, build plan
```

## Building

- **Open in Xcode**: `./scripts/bootstrap.sh`, then open
  `RouteWarrior.xcodeproj`.
- **Onto a phone**: set your team once —
  `echo 'ROUTEWARRIOR_TEAM=YOURTEAMID' > scripts/signing.local` — then
  `./scripts/device-build.sh`.
- **Kit tests**: plain `swift test` on any Mac; no simulator needed.

## Signing, in one paragraph

`project.yml` carries no team and turns signing off, so CI builds unsigned
and no developer account ever reaches the repository. For device builds, put
your team ID in the gitignored `scripts/signing.local` once and
`./scripts/device-build.sh` passes it on the `xcodebuild` command line. Never
add signing settings to `project.yml` or in Xcode's Signing & Capabilities
pane: the first breaks CI, and the second is silently discarded the next
time the project is regenerated.

## The two rules that cost the most to learn

1. **Never `killall CoreSimulatorService`.** It unmounts the simulator
   runtime, which `actool` needs even for device-only builds; recovery is an
   8 GB redownload.
2. **The generated project is disposable.** Anything configured through
   Xcode's UI lasts only until the next `xcodegen generate`. If a setting
   matters, it goes in `project.yml` — the App Group and iCloud entitlements
   for the app and widget targets already live there for exactly this
   reason.
