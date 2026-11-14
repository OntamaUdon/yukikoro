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

shot grow-morning  -yukikoro-demo -yukikoro-hour 6.3
shot grow-day      -yukikoro-demo -yukikoro-hour 12
shot grow-dusk     -yukikoro-demo -yukikoro-hour 17.7  -yukikoro-steps 9000
shot grow-night    -yukikoro-demo -yukikoro-hour 22    -yukikoro-steps 12500
shot decorate-day  -yukikoro-demo -yukikoro-hour 12 -yukikoro-decorate
shot decorate-sel  -yukikoro-demo -yukikoro-hour 15 -yukikoro-decorate -yukikoro-select
shot decorate-dusk -yukikoro-demo -yukikoro-hour 17.7 -yukikoro-decorate
shot decorate-night -yukikoro-demo -yukikoro-hour 22 -yukikoro-decorate
shot onboarding
