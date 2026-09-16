#!/usr/bin/env zsh
# App Store screenshots: runs the screenshot UI tests per device and language, exports the PNGs.
#   scripts/screenshots.sh                          # every device, en + fr
#   DEVICES="iPhone 17 Pro Max" LANGS=en scripts/screenshots.sh
#   WATCH_DEVICES="" scripts/screenshots.sh         # phone and iPad only
#   DARK=1 scripts/screenshots.sh                   # dark appearance (iPhone/iPad)
# Output: Screenshots/<lang>/<device>/<name>.png
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICES=${DEVICES-"iPhone 17 Pro Max|iPad Pro 13-inch (M5)"}
WATCH_DEVICES=${WATCH_DEVICES-"Apple Watch Series 11 (46mm)|Apple Watch Ultra 3 (49mm)"}
LANGS=${LANGS:-"en fr"}
DARK=${DARK:-0}
OUT=Screenshots
WORK=$(mktemp -d)

# shoot <device> <scheme> <test> <bundle id> : one xcodebuild run per language, PNGs into $OUT.
shoot() {
  local device=$1 scheme=$2 test=$3 bundle=$4
  # Newest runtime wins: an older-OS twin of the same name cannot run an iOS 26 app.
  local udid
  udid=$(xcrun simctl list devices available -j | jq -r --arg n "$device" '.devices | to_entries | sort_by(.key) | reverse | .[].value[] | select(.name==$n) | .udid' | head -1)
  [[ -n "$udid" ]] || { echo "no simulator named '$device'"; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  # A store left by an older build can fail to migrate; the app then runs on a fallback store and
  # the screenshots lie. Start from nothing.
  xcrun simctl uninstall "$udid" "$bundle" 2>/dev/null || true
  # Watch simulators have no status bar to override.
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

  for lang in ${=LANGS}; do
    local slug=${device// /-}; slug=${slug//[()]/}
    local dest="$OUT/$lang/$slug"; [[ $DARK == 1 ]] && dest="$dest-dark"
    local result="$WORK/$slug-$lang.xcresult"
    echo "▶ $device · $lang"
    # TEST_RUNNER_ variables reach the test process only from the environment, not as arguments.
    TEST_RUNNER_SCREENSHOT_LANGUAGE="$lang" TEST_RUNNER_SCREENSHOT_DARK="$DARK" \
    xcodebuild test -project Ondelia.xcodeproj -scheme "$scheme" \
      -destination "id=$udid" -only-testing:"$test" \
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
  xcrun simctl status_bar "$udid" clear 2>/dev/null || true
}

for device in ${(s:|:)DEVICES}; do
  shoot "$device" Ondelia OndeliaUITests/ScreenshotUITests io.jayet.Isora
done
for device in ${(s:|:)WATCH_DEVICES}; do
  shoot "$device" "OndeliaWatch Watch App" "OndeliaWatch Watch AppUITests/WatchScreenshotUITests" io.jayet.Isora.watchkitapp
done
echo "done: $OUT"
