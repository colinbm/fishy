#!/usr/bin/env bash
# Captures App Store screenshots of Fishy on iPhone 6.9", iPad 13" and Apple TV simulators into
# AppStore/screenshots/{iphone,ipad,tv}, replacing what is there. Uses its own simulators (created on
# first run) so it never disturbs ones in use. Fish swap every few seconds while capturing, and
# Tools/pick_screenshots.swift keeps frames with a whole fish in view, in different colours.
#
# Usage: Tools/screenshots.sh [count per device, default 4]
set -euo pipefail
cd "$(dirname "$0")/.."
COUNT="${1:-4}"
BUNDLE_ID=com.colinbm.fishy
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

device() { # name, device type → UDID (created if missing, on a runtime that supports the type)
  local udid
  udid=$(xcrun simctl list devices -j | python3 -I -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == sys.argv[1] and d['isAvailable']: print(d['udid']); sys.exit()" "$1")
  if [ -z "$udid" ]; then
    local runtime
    runtime=$(xcrun simctl list runtimes -j | python3 -I -c "
import json, sys
ok = [r['identifier'] for r in json.load(sys.stdin)['runtimes']
      if r['isAvailable'] and any(t['identifier'] == sys.argv[1] for t in r.get('supportedDeviceTypes', []))]
print(ok[-1] if ok else '')" "$2")
    [ -n "$runtime" ] || { echo "No installed runtime supports $2" >&2; exit 1; }
    udid=$(xcrun simctl create "$1" "$2" "$runtime")
  fi
  echo "$udid"
}


capture() { # folder, platform dir, simulator UDID, frames
  local folder=$1 products=$2 udid=$3 frames=$4 out="AppStore/screenshots/$1"
  echo "== $folder"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$WORK/dd/Build/Products/$products/Fishy.app"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" -swapSeconds 5 >/dev/null
  sleep 3
  mkdir -p "$WORK/$folder"
  for i in $(seq -w 1 "$frames"); do
    xcrun simctl io "$udid" screenshot --type=png "$WORK/$folder/$i.png" >/dev/null 2>&1
    sleep 0.6
  done
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  mkdir -p "$out"
  find "$out" -name '*.png' -delete
  local n=1
  while read -r frame; do
    cp "$frame" "$out/$n.png"; n=$((n + 1))
  done < <(swift Tools/pick_screenshots.swift "$COUNT" "$WORK/$folder"/*.png)
  echo "$((n - 1)) screenshots in $out"
}

echo "Building for the simulators…"
for platform in "iOS Simulator" "tvOS Simulator"; do
  xcodebuild -project Fishy.xcodeproj -scheme Fishy -configuration Debug -destination "generic/platform=$platform" \
    -derivedDataPath "$WORK/dd" build -quiet
done

capture iphone Debug-iphonesimulator "$(device "Fishy Screenshots iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max)" 40
capture ipad Debug-iphonesimulator "$(device "Fishy Screenshots iPad" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB)" 40
capture tv Debug-appletvsimulator "$(device "Fishy Screenshots TV" com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K)" 40
