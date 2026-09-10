#!/usr/bin/env bash
# One command from the current checkout to an App Store archive.
#
# Like device-build.sh, this exists because project.yml deliberately carries no
# team and no key: CI builds unsigned, and nothing that identifies an account
# ever reaches the repository. The archive needs both, and takes them from the
# same place device-build.sh does (the environment, or gitignored
# scripts/signing.local). One thing it never takes is ROUTEWARRIOR_FORCE_PRO:
# an archive is what ships, and a shipped build must earn Pro through StoreKit.
#
#   ./scripts/archive.sh            archive, then open it in Xcode's Organizer
#                                   (Distribute App → App Store Connect → Upload)
#   ./scripts/archive.sh --upload   archive and upload from the command line,
#                                   using the Apple ID signed into Xcode
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=RouteWarrior
CONFIG=Release
ARCHIVE=build/archive/$SCHEME.xcarchive
EXPORT=build/archive/export

# --- who is signing, and which key ----------------------------------------
TEAM="${ROUTEWARRIOR_TEAM:-}"
ROUTES_KEY="${ROUTEWARRIOR_ROUTES_KEY:-}"
if [ -f scripts/signing.local ]; then
    # shellcheck disable=SC1091
    . scripts/signing.local
    TEAM="${TEAM:-${ROUTEWARRIOR_TEAM:-}}"
    ROUTES_KEY="${ROUTES_KEY:-${ROUTEWARRIOR_ROUTES_KEY:-}}"
fi
if [ -z "$TEAM" ]; then
    echo "No signing team set. See scripts/device-build.sh for how to set ROUTEWARRIOR_TEAM." >&2
    exit 1
fi
if [ -z "$ROUTES_KEY" ]; then
    cat >&2 <<'MSG'
No Google Routes key set (ROUTEWARRIOR_ROUTES_KEY). An archive without it
ships a build in which Google's plan, the Google map and Pro's Google
comparison never work. Add the key to scripts/signing.local and re-run:

    echo 'ROUTEWARRIOR_ROUTES_KEY=AIza...' >> scripts/signing.local
MSG
    exit 1
fi

# --- regenerate, archive ----------------------------------------------------
echo "==> Generating the project"
./scripts/bootstrap.sh >/dev/null
rm -rf "$ARCHIVE" "$EXPORT"

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
echo "==> Archiving $SCHEME $VERSION ($BUILD), $CONFIG, team $TEAM — Pro is NOT forced"
xcodebuild \
    -project "$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ROUTEWARRIOR_ROUTES_KEY="$ROUTES_KEY" \
    ROUTEWARRIOR_FORCE_PRO="" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY="Apple Development" \
    archive

[ -d "$ARCHIVE" ] || { echo "FAIL: archive reported success but $ARCHIVE is missing" >&2; exit 1; }
echo "==> Archived $ARCHIVE"

# Refuse to ship a build that could report Pro without a purchase.
PLIST="$ARCHIVE/Products/Applications/$SCHEME.app/Info.plist"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :RouteWarriorForcePro' "$PLIST" 2>/dev/null || true)" = "1" ]; then
    echo "FAIL: the archive has RouteWarriorForcePro=1 — never ship that" >&2
    exit 1
fi

# --- hand off, or upload ----------------------------------------------------
if [ "${1:-}" != "--upload" ]; then
    echo "==> Opening the archive in Xcode's Organizer."
    echo "    Distribute App → App Store Connect → Upload, defaults on every page."
    echo "    While it is open: right-click the archive → Generate Privacy Report"
    echo "    (docs/APP_STORE_SUBMISSION.md §4)."
    open "$ARCHIVE"
    exit 0
fi

# The export options carry the team, so they are written here, not committed.
OPTIONS="$(mktemp -t ExportOptions).plist"; trap 'rm -f "$OPTIONS"' EXIT
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
echo "==> Uploading to App Store Connect as the Apple ID signed into Xcode"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates
echo "==> Uploaded. It appears under TestFlight → Builds after processing (10–30 min)."
