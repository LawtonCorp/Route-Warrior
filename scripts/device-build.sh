#!/usr/bin/env bash
# One command to put the current checkout on a phone in your hand.
#
# Why this exists. `project.yml` deliberately holds no team and switches code
# signing off, so CI can build unsigned and no developer account ever reaches the
# repository. That leaves a device build needing four settings the generated
# project does not carry, and `xcodegen generate` discards anything Xcode's UI
# wrote — so setting them in Signing & Capabilities works until the next
# regeneration and then silently stops. Supplying them here means the answer
# survives every regeneration, because it was never in the project to begin with.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=RouteWarrior
CONFIG=Debug
DERIVED=build/device
APP="$DERIVED/Build/Products/$CONFIG-iphoneos/$SCHEME.app"

# --- who is signing -------------------------------------------------------
TEAM="${ROUTEWARRIOR_TEAM:-}"
ROUTES_KEY="${ROUTEWARRIOR_ROUTES_KEY:-}"
FORCE_PRO="${ROUTEWARRIOR_FORCE_PRO:-}"
if [ -f scripts/signing.local ]; then
    # shellcheck disable=SC1091
    . scripts/signing.local
    TEAM="${TEAM:-${ROUTEWARRIOR_TEAM:-}}"
    ROUTES_KEY="${ROUTES_KEY:-${ROUTEWARRIOR_ROUTES_KEY:-}}"
    FORCE_PRO="${FORCE_PRO:-${ROUTEWARRIOR_FORCE_PRO:-}}"
fi
if [ -z "$TEAM" ]; then
    cat >&2 <<'MSG'
No signing team set.

Set it once and every later build picks it up:

    echo 'ROUTEWARRIOR_TEAM=YOURTEAMID' > scripts/signing.local

scripts/signing.local is gitignored, so your account never reaches the
repository. For a single build instead:

    ROUTEWARRIOR_TEAM=YOURTEAMID ./scripts/device-build.sh

Your Team ID is in Xcode → Settings → Accounts, or on the Apple Developer
site under Membership.
MSG
    exit 1
fi

# --- regenerate, because files may have been added since the last one -----
echo "==> Generating the project"
./scripts/bootstrap.sh >/dev/null

# --- build ----------------------------------------------------------------
# -allowProvisioningUpdates is what lets xcodebuild register the bundle IDs
# with the portal on its own; without it a first build on a new machine fails
# on provisioning rather than on anything you wrote.
echo "==> Building $SCHEME ($CONFIG) for device, team $TEAM"
[ "$FORCE_PRO" = "1" ] && echo "==> Pro tier FORCED ON for this build (D-017 owner override)"
xcodebuild \
    -project "$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    ROUTEWARRIOR_ROUTES_KEY="$ROUTES_KEY" \
    ROUTEWARRIOR_FORCE_PRO="$FORCE_PRO" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY="Apple Development" \
    build

[ -d "$APP" ] || { echo "FAIL: build reported success but $APP is missing" >&2; exit 1; }
echo "==> Built $APP"

# --- install --------------------------------------------------------------
if [ "${1:-}" = "--build-only" ]; then
    echo "Build only, as asked. Install it with:"
    echo "    xcrun devicectl device install app --device <name-or-udid> \"$APP\""
    exit 0
fi

DEVICE="${ROUTEWARRIOR_DEVICE:-}"
if [ -z "$DEVICE" ]; then
    # Pick the phone automatically when exactly one is plugged in; anything
    # less certain is the user's call, not this script's.
    LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
    xcrun devicectl list devices --json-output "$LIST" >/dev/null 2>&1 || true
    DEVICE="$(python3 - "$LIST" <<'PY' 2>/dev/null || true
import json, sys

# Two filters, and both are needed. `pairingState` alone is not enough: a paired
# Apple Watch that is nowhere near the Mac still reports as paired, so a desk
# with a phone and a watch on it looks like two candidates and the script gives
# up on a choice that was never ambiguous. What separates them is the State
# column devicectl prints -- tunnelState -- plus the platform, since only an
# iOS device can run this app.
def field(device, *path, default=""):
    for key in path:
        device = device.get(key, {}) if isinstance(device, dict) else {}
    return device if isinstance(device, str) else default

try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)

candidates = []
for d in devices:
    name = field(d, "deviceProperties", "name")
    state = field(d, "connectionProperties", "tunnelState")
    platform = field(d, "hardwareProperties", "platform")
    kind = field(d, "hardwareProperties", "deviceType")
    if not name or state != "connected":
        continue
    if platform and platform != "iOS":
        continue
    if not platform and kind and kind not in ("iPhone", "iPad"):
        continue
    candidates.append(name)

if len(candidates) == 1:
    print(candidates[0])
PY
)"
fi

if [ -z "$DEVICE" ]; then
    echo
    echo "Could not settle on one device. Connected devices:"
    xcrun devicectl list devices || true
    echo
    echo "Pick one and re-run:"
    echo "    ROUTEWARRIOR_DEVICE='Your iPhone' ./scripts/device-build.sh"
    exit 1
fi

echo "==> Installing on $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo
echo "Done. Open $SCHEME on the phone."
