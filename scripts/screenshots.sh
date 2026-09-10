#!/usr/bin/env zsh
# App Store screenshots: runs ScreenshotUITests on each device and language, exports the PNGs.
#   scripts/screenshots.sh                 # all devices, en + fr
#   DEVICES="iPhone 17 Pro Max" LANGS=en scripts/screenshots.sh
#   DARK=1 scripts/screenshots.sh          # dark appearance
# Output: Screenshots/<lang>/<device>/<name>.png
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICES=${DEVICES:-"iPhone 17 Pro Max|iPad Pro 13-inch (M5)"}
LANGS=${LANGS:-"en fr"}
DARK=${DARK:-0}
OUT=Screenshots
WORK=$(mktemp -d)

for device in ${(s:|:)DEVICES}; do
  udid=$(xcrun simctl list devices available -j | jq -r --arg n "$device" '.devices | to_entries | sort_by(.key) | reverse | .[].value[] | select(.name==$n) | .udid' | head -1)
  [[ -n "$udid" ]] || { echo "no simulator named '$device'"; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

  for lang in ${=LANGS}; do
    slug=${device// /-}; slug=${slug//[()]/}
    dest="$OUT/$lang/$slug"; [[ $DARK == 1 ]] && dest="$dest-dark"
    result="$WORK/$slug-$lang.xcresult"
    echo "▶ $device · $lang"
    # TEST_RUNNER_ variables reach the test process only from the environment, not as arguments.
    TEST_RUNNER_SCREENSHOT_LANGUAGE="$lang" TEST_RUNNER_SCREENSHOT_DARK="$DARK" \
    xcodebuild test -project Isora.xcodeproj -scheme Isora \
      -destination "id=$udid" -only-testing:IsoraUITests/ScreenshotUITests \
      -resultBundlePath "$result" -parallel-testing-enabled NO -quiet

    rm -rf "$dest"; mkdir -p "$dest"
    xcrun xcresulttool export attachments --path "$result" --output-path "$WORK/export" >/dev/null
    jq -r '.. | objects | select(has("exportedFileName")) | "\(.exportedFileName)\t\(.suggestedHumanReadableName)"' "$WORK/export/manifest.json" |
      while IFS=$'\t' read -r file human; do
        mv "$WORK/export/$file" "$dest/${human%%_*}.png"
      done
    rm -rf "$WORK/export"
    ls "$dest"
  done
  xcrun simctl status_bar "$udid" clear
done
echo "done: $OUT"
