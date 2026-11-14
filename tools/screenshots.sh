#!/bin/bash
# CI 用: シミュレーターでアプリを起動して画面を撮る。 使い方: tools/screenshots.sh <Yukikoro.app のパス> <出力ディレクトリ>
set -euo pipefail
APP="$1"
OUT="$2"
BUNDLE="com.example.yukikoro"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}')
echo "Simulator: $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"

shot() {
  local name="$1"; shift
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 9
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  xcrun simctl terminate "$UDID" "$BUNDLE" || true
}

shot home-day      -yukikoro-demo -yukikoro-hour 11
shot home-night    -yukikoro-demo -yukikoro-hour 22 -yukikoro-steps 12500
shot home-small    -yukikoro-demo -yukikoro-hour 17 -yukikoro-steps 700
shot home-xl       -yukikoro-demo -yukikoro-hour 9  -yukikoro-steps 26000
shot collection    -yukikoro-demo -yukikoro-hour 11 -yukikoro-tab 1
shot settings      -yukikoro-demo -yukikoro-hour 11 -yukikoro-tab 2
shot complete      -yukikoro-demo -yukikoro-hour 11 -yukikoro-complete
shot g3d-0         -yukikoro-gallery3d 0
shot g3d-1         -yukikoro-gallery3d 1
shot snap-0        -yukikoro-snap 0
shot ball-day      -yukikoro-ball 4200 -yukikoro-hour 11
shot ball-night    -yukikoro-ball 12500 -yukikoro-hour 22
shot onboarding
