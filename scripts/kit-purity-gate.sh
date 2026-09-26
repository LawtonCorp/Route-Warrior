#!/usr/bin/env bash
# RouteWarriorKit must be UI-free so every rule of the app is testable without a
# simulator, and additionally CoreLocation/SwiftData-free so algorithms never
# grow Apple-type dependencies (the app converts CLLocation at the boundary;
# persistence lives in RouteWarriorStore). RouteWarriorStore may use SwiftData
# but no UI framework. Any violation fails the build.
set -euo pipefail
cd "$(dirname "$0")/.."

STATUS=0
UI_FRAMEWORKS='UIKit|SwiftUI|AppKit|SpriteKit|CoreGraphics|QuartzCore'
IMPORT_RE='^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+'

echo "Purity gate: RouteWarriorKit must import no UI framework, CoreLocation, or SwiftData"
if hits=$(grep -r -n -E "${IMPORT_RE}(${UI_FRAMEWORKS}|CoreLocation|SwiftData|MapKit|WidgetKit|ActivityKit)\b" Sources/RouteWarriorKit 2>/dev/null); then
    echo "FAIL: forbidden import in RouteWarriorKit:"
    echo "$hits"
    STATUS=1
else
    echo "  ok: RouteWarriorKit is pure"
fi

echo "Purity gate: RouteWarriorStore must import no UI framework"
if hits=$(grep -r -n -E "${IMPORT_RE}(${UI_FRAMEWORKS})\b" Sources/RouteWarriorStore 2>/dev/null); then
    echo "FAIL: UI framework imported in RouteWarriorStore:"
    echo "$hits"
    STATUS=1
else
    echo "  ok: RouteWarriorStore imports no UI framework"
fi

echo "Identity gate: every iCloud container in project.yml is the one the store opens (D-086)"
STORE_CONTAINER=$(grep -o 'iCloud\.[A-Za-z0-9.]*' Sources/RouteWarriorStore/StoreFactory.swift | head -1)
YML_CONTAINERS=$(grep -o 'iCloud\.[A-Za-z0-9]*\.[A-Za-z0-9.]*' project.yml | sort -u)
if [ -z "$STORE_CONTAINER" ] || [ "$YML_CONTAINERS" != "$STORE_CONTAINER" ]; then
    echo "FAIL: StoreFactory opens '$STORE_CONTAINER' but project.yml declares:"
    echo "$YML_CONTAINERS"
    STATUS=1
else
    echo "  ok: $STORE_CONTAINER in both"
fi

if [ "$STATUS" -eq 0 ]; then echo "PURITY PASS"; else echo "PURITY FAIL"; fi
exit "$STATUS"
