#!/bin/bash
# Runs the UI screenshot tour on a simulator (no Xcode window needed) and exports the
# screenshots to build/screenshots/. Usage: scripts/screenshot-tour.sh [simulator name]
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 18 Pro}"
RESULT=build/screenshot-tour.xcresult
OUT=build/screenshots

(cd iosApp && xcodegen --quiet)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
# Clean, consistent status bar.
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4

rm -rf "$RESULT" "$OUT"
xcodebuild -project iosApp/LocalTracks.xcodeproj -scheme ScreenshotTour \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build/DerivedData -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO test > build/screenshot-tour.log 2>&1 \
  || { grep -E "error:|failed|\*\* TEST" build/screenshot-tour.log; echo "Tour failed; full log in build/screenshot-tour.log"; exit 1; }

mkdir -p "$OUT"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" >/dev/null
# Rename the exported files (UUIDs) to the names given in the tour, e.g. 01-record.png.
jq -r '.[].attachments[] | select(.exportedFileName | endswith(".png")) | "\(.exportedFileName) \(.suggestedHumanReadableName)"' "$OUT/manifest.json" |
  while read -r file name; do mv "$OUT/$file" "$OUT/${name%%_*}.png"; done
rm "$OUT/manifest.json"
echo "Screenshots in $OUT:"
ls "$OUT"
