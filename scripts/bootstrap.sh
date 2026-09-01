#!/usr/bin/env bash
# One command to turn a fresh clone into an Xcode project you can open.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Installing XcodeGen via Homebrew..."
    brew install xcodegen
fi

xcodegen generate
echo
echo "Done. Open StarterApp.xcodeproj in Xcode, or run:  open StarterApp.xcodeproj"
