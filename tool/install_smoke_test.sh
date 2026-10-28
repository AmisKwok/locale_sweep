#!/usr/bin/env bash
# Installs locale_sweep from pub.dev into a fresh Flutter app and runs a sweep.
#
# Usage: tool/install_smoke_test.sh [version]   (default: latest)
# Requires flutter and dart on PATH.
set -euo pipefail

VERSION="${1:-}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

APP="$WORK_DIR/smoke_app"
flutter create --empty --project-name smoke_app "$APP" >/dev/null
cd "$APP"

flutter pub add --dev "locale_sweep${VERSION:+:$VERSION}"
INSTALLED="$(flutter pub deps --style=compact | sed -n 's/^- locale_sweep \([^ ]*\).*/\1/p')"
echo "Installed locale_sweep $INSTALLED"

mkdir -p test/sweep
cat > test/sweep/smoke_test.dart <<'DART'
import 'package:flutter/material.dart';
import 'package:locale_sweep/locale_sweep.dart';

void main() {
  sweepTest(
    'smoke',
    builder: () => const MaterialApp(
      home: Scaffold(body: Center(child: Text('Settings'))),
    ),
    locales: ['en', pseudoLocale],
    textScales: [1.0],
    viewports: [ViewportPreset.phone],
    captureScreenshots: false,
  );
}
DART

dart run locale_sweep run --fail-on none

python3 - .locale_sweep/reports/report.json <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
locales = sorted(r["locale"] for r in report["results"])
assert locales == ["en", "pseudo"], f"unexpected variants: {locales}"
assert not report["executionErrors"], report["executionErrors"]
print(f"Report OK: {len(locales)} variants ({', '.join(locales)})")
PY

echo "Smoke test passed for locale_sweep $INSTALLED"
