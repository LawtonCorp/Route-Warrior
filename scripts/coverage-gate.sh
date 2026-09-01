#!/usr/bin/env bash
# StarterKit must hold >= 90% line coverage. Run after
# `swift test --enable-code-coverage`.
set -euo pipefail
cd "$(dirname "$0")/.."

THRESHOLD="${COVERAGE_THRESHOLD:-90}"

PROF=$(find .build -name 'default.profdata' -print -quit 2>/dev/null || true)
if [ -z "$PROF" ]; then
    echo "FAIL: no coverage profile found. Run: swift test --enable-code-coverage"
    exit 1
fi

BIN=$(find .build -name '*PackageTests.xctest' -print -quit 2>/dev/null || true)
if [ -d "$BIN" ]; then BIN="$BIN/Contents/MacOS/$(basename "$BIN" .xctest)"; fi
if [ ! -f "$BIN" ]; then
    echo "FAIL: could not locate the test binary for coverage export."
    exit 1
fi

xcrun llvm-cov export -format=lcov -instr-profile "$PROF" "$BIN" > /tmp/starterkit.lcov

python3 - "$THRESHOLD" <<'PY'
import sys
threshold = float(sys.argv[1])
hit = total = 0
keep = False
per_file = {}
cur = None
for line in open('/tmp/starterkit.lcov'):
    line = line.strip()
    if line.startswith('SF:'):
        path = line[3:]
        keep = '/Sources/StarterKit/' in path
        cur = path.split('/Sources/StarterKit/')[-1] if keep else None
        if keep:
            per_file.setdefault(cur, [0, 0])
    elif keep and line.startswith('DA:'):
        _, counts = line.split(':', 1)
        _, count = counts.split(',')
        total += 1
        per_file[cur][1] += 1
        if int(count) > 0:
            hit += 1
            per_file[cur][0] += 1

if total == 0:
    print("FAIL: no StarterKit lines were instrumented.")
    sys.exit(1)

pct = 100.0 * hit / total
print(f"StarterKit line coverage: {pct:.2f}% ({hit}/{total} lines)")
print()
for name, (h, t) in sorted(per_file.items(), key=lambda kv: kv[1][0] / kv[1][1] if kv[1][1] else 1):
    if t:
        print(f"  {100.0*h/t:6.2f}%  {h:5d}/{t:<5d}  {name}")
print()
if pct + 1e-9 < threshold:
    print(f"COVERAGE FAIL: {pct:.2f}% is below the {threshold:.0f}% floor.")
    sys.exit(1)
print(f"COVERAGE PASS: {pct:.2f}% meets the {threshold:.0f}% floor.")
PY
