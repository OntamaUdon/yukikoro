#!/bin/bash
# CI 用: シミュレーターでアプリを起動して画面を撮る。 使い方: tools/screenshots.sh <Yukikoro.app のパス> <出力ディレクトリ>
set -euo pipefail
APP="$1"
OUT="$2"
BUNDLE="com.ontamaudon.yukikoro"
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

shot home-morning  -yukikoro-demo -yukikoro-hour 6.3
shot home-day      -yukikoro-demo -yukikoro-hour 12
shot home-dusk     -yukikoro-demo -yukikoro-hour 17.7  -yukikoro-steps 9000
shot home-night    -yukikoro-demo -yukikoro-hour 22    -yukikoro-steps 12500
shot stock         -yukikoro-demo -yukikoro-hour 12 -yukikoro-tab 1
shot artworks      -yukikoro-demo -yukikoro-hour 12 -yukikoro-tab 2
shot compose-day   -yukikoro-demo -yukikoro-hour 12 -yukikoro-tab 2 -yukikoro-compose
shot compose-sel   -yukikoro-demo -yukikoro-hour 15 -yukikoro-tab 2 -yukikoro-compose -yukikoro-select
shot compose-dusk  -yukikoro-demo -yukikoro-hour 17.7 -yukikoro-tab 2 -yukikoro-compose
shot compose-night -yukikoro-demo -yukikoro-hour 22 -yukikoro-tab 2 -yukikoro-compose
shot sculpt        -yukikoro-demo -yukikoro-hour 12 -yukikoro-tab 1 -yukikoro-sculpt
shot onboarding
