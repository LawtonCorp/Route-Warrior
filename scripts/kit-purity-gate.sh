#!/usr/bin/env bash
# StarterKit must be UI-free so every rule of the app is testable without a
# simulator. Any UI framework import in the kit fails the build.
set -euo pipefail
cd "$(dirname "$0")/.."

STATUS=0
echo "Purity gate: StarterKit must import no UI framework"

if hits=$(grep -r -n -E '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+(UIKit|SwiftUI|AppKit|SpriteKit|CoreGraphics|QuartzCore)\b' Sources/StarterKit 2>/dev/null); then
    echo "FAIL: UI framework imported in StarterKit:"
    echo "$hits"
    STATUS=1
else
    echo "  ok: no UI framework imports"
fi

if [ "$STATUS" -eq 0 ]; then echo "PURITY PASS"; else echo "PURITY FAIL"; fi
exit "$STATUS"
