# ios-starter

A template for new LawtonCorp iPhone apps. It is a complete, working app that
does nothing — the value is the plumbing around it, distilled from building
Letterama: XcodeGen project generation, one-command device install with signing
kept out of git, a UI-free core package testable without a simulator, and a CI
pipeline that is green from the first push.

Day one with this template ends with a green CI badge and an app icon on your
phone. Without it, day one is usually spent discovering why neither happens.

## Starting a new app from this template

1. On GitHub: **Use this template → Create a new repository** (this repo must be
   marked as a template under Settings → Template repository).
2. Clone it, then work through the rename checklist below.
3. `./scripts/bootstrap.sh` → open the project in Xcode, or
   `./scripts/device-build.sh` → app on your phone.

If an AI coding agent will work in the repo, nothing extra is needed:
`CLAUDE.md` is read automatically at the start of every session and carries the
rules that were learned expensively.

## Rename checklist

The placeholder product is **StarterApp** and the core package is
**StarterKit**. To rename to `YourApp` / `YourAppKit`:

| Where | What |
|---|---|
| `project.yml` | `name:`, target names, `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleDisplayName` |
| `Package.swift` | package name, product, target names |
| `Sources/StarterKit/` → `Sources/YourAppKit/` | directory rename |
| `Tests/StarterKitTests/` → `Tests/YourAppKitTests/` | directory rename |
| `App/StarterApp/` → `App/YourApp/`, `App/StarterAppTests/` → … | directory rename |
| `App/*/…swift` | `import StarterKit`, the `@main` struct name |
| `scripts/bootstrap.sh`, `scripts/device-build.sh` | the scheme name and the printed messages |
| `scripts/kit-purity-gate.sh`, `scripts/coverage-gate.sh` | the `Sources/StarterKit` paths |
| `.github/workflows/ci.yml` | the `-project` / `-scheme` values |
| `CLAUDE.md`, this README | the names in prose |

A case-sensitive project-wide search for `Starter` finds every instance.

## What's here

```
project.yml               XcodeGen definition; the .xcodeproj is generated, not committed
Package.swift             StarterKit — the UI-free core package
Sources/StarterKit/       app logic lives here, testable with plain `swift test`
Tests/StarterKitTests/    kit tests (Swift Testing)
App/StarterApp/           thin SwiftUI app over the kit
App/StarterAppTests/      app-target tests — wiring, not logic
scripts/bootstrap.sh      clone → openable Xcode project
scripts/device-build.sh   clone → app installed on your iPhone, one command
scripts/kit-purity-gate.sh   CI gate: no UI framework imports in the kit
scripts/coverage-gate.sh     CI gate: kit line coverage ≥ 90%
.github/workflows/ci.yml  three jobs: Linux gates, kit tests, simulator app build
CLAUDE.md                 the working rules, loaded automatically by Claude Code
```

## Signing, in one paragraph

`project.yml` carries no team and turns signing off, so CI builds unsigned and
no developer account ever reaches the repository. For device builds, put your
team ID in a gitignored file once —
`echo 'STARTER_TEAM=YOURTEAMID' > scripts/signing.local` — and
`./scripts/device-build.sh` passes it on the `xcodebuild` command line. Never
add signing settings to `project.yml` or in Xcode's Signing & Capabilities pane:
the first breaks CI, and the second is silently discarded the next time the
project is regenerated.

## The two rules that cost the most to learn

1. **Never `killall CoreSimulatorService`.** It unmounts the simulator runtime,
   which `actool` needs even for device-only builds; recovery is an 8 GB
   redownload.
2. **The generated project is disposable.** Anything configured through Xcode's
   UI lasts only until the next `xcodegen generate`. If a setting matters, it
   goes in `project.yml`.
