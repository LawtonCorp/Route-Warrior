# Route Warrior — Build Plan

Status: v1.0 (approved 2026-09-01). Milestones for `REQUIREMENTS.md` /
`SPEC.md`; each lands as one or more PRs with CI green, `DECISIONS.md`
updated per behaviour change, and kit coverage ≥ 90% throughout.

Working constraints: GitHub Actions is the only compiler when developing
from Claude Code on the web (run `./scripts/kit-purity-gate.sh` locally,
read diffs adversarially, fetch CI logs via the GitHub MCP tools). Claims
are split honestly: algorithms and wiring are machine-checked in CI;
battery, auto-detect reliability, Live Activity feel, and CloudKit sync
behavior are phone-in-hand field tests.

## M0 — Rename pass (1 PR)

`Starter*` → `RouteWarrior*` per the README checklist (`project.yml`,
`Package.swift`, `Sources/`, `Tests/`, `App/`, scripts, CI workflow,
prose). Add the `RouteWarriorStore` package target and the
`RouteWarriorWidgets` extension stub to `project.yml`, declaring the App
Group (`group.com.lawtoncorp.routewarrior`) and iCloud/CloudKit
entitlements for **both** app and widget targets.

**Exit**: CI green; app installs on Brian's phone via
`./scripts/device-build.sh`.

## M1 — Kit core (3–4 PRs)

1. Domain value types + polyline encoding/resampling utilities.
2. TripRecorder state machine + StopDetector.
3. RouteMatcher + DestinationPredictor.
4. StatsEngine + Verdict + GhostRaceEngine + TierPolicy.

Test fixtures: hand-constructed synthetic streams **plus** real GPX traces
Brian records with an off-the-shelf GPX logger — independent reference
data, per the verification philosophy (the kit must not grade its own
homework).

**Exit**: `swift test` green, kit coverage ≥ 90%.

## M2 — Recording app (2–3 PRs)

LocationService, auto start/stop wiring, Store layer + CloudKit sync,
Places CRUD, Trips list/detail with MapKit, manual record. App-target
wiring tests for every kit/app boundary.

**Exit**: CI green **and** one week of Brian's real driving captured
correctly (field test: no missed trips, no phantom trips, believable
battery).

## M3 — Comparisons & analytics (2–3 PRs)

SnapshotService + DestinationPredictor wiring, followed/deviated labeling,
OverpassService + IntersectionInventory, destination analytics screens +
verdict card. Verify current Google Routes API pricing/SKUs here before
committing to free-tier limits.

**Exit**: real trips show Google-vs-actual deltas; stop/signal counts sane
on Brian's known routes (field ground truth: he counts the actual signs
once and we compare).

## M4 — Ghost race (1–2 PRs)

ActivityKit integration + widget-extension UI (lock screen + Dynamic
Island), live route projection.

**Exit**: lock-screen ahead/behind delta updates through a real drive
without foregrounding the app (field).

## M5 — Monetization & onboarding (2 PRs)

StoreKit 2 + paywall + TierPolicy gates (prices decided here), onboarding
+ permission primers, app icon, empty states, polish pass.

**Exit**: purchase/restore round-trips in sandbox; free-tier limits
enforced; onboarding reviewed on-device.

## M6 — App Store (1–2 PRs + release ops)

Privacy manifest, privacy policy + App Privacy labels, App Review notes +
demo video justifying Always location, screenshots, TestFlight external
beta (2+ weeks — auto-detect reliability and battery feedback from
testers), then submission.

**Exit**: approved and live. App Review pushback on Always location is the
top schedule risk; the mitigation is prepared justification plus the
manual-record fallback demo.

## Top risks

| Risk | Mitigation |
|---|---|
| App Review rejects Always-location use | Strong justification + education flow + manual-mode fallback demo |
| Google API cost/abuse at scale | Bundle-restricted key, hard quotas, confidence-gated snapshots, keyless proxy later |
| OSM stop-sign coverage is patchy | Honest per-variant confidence labels; motion-inferred counts alongside |
| Destination prediction cold start | One-tap manual pick; prediction improves with history |
| Battery perception kills reviews | Ultra-cheap armed mode; tester telemetry during beta |
