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
  sleep "${DELAY:-8}"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  xcrun simctl terminate "$UDID" "$BUNDLE" || true
}

# 重さ(kg) 80 = 直径 0.8m、2200 = 直径 2.4m（最初の木の道にほぼ収まる）、1e6 = 次の道
shot night-2400    -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 2200 -yukikoro-crew 1,6
shot night-small   -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 160  -yukikoro-crew 0,3
shot day-2400      -yukikoro-demo -yukikoro-hour 12   -yukikoro-mass 2200 -yukikoro-crew 1,6
shot dusk-2400     -yukikoro-demo -yukikoro-hour 17.7 -yukikoro-mass 2200 -yukikoro-crew 2,3
shot menu          -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 2200 -yukikoro-crew 1,6 -yukikoro-sheet menu
shot onboarding
shot falling         -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 5400 -yukikoro-crew 2,3
shot night-stage2  -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 800000 -yukikoro-crew 4,2
shot stage-pole      -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 200000 -yukikoro-crew 3,2
shot stage-house0    -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 800000 -yukikoro-crew 3,2
shot stage-house     -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 2e8 -yukikoro-crew 4,3 -yukikoro-gravity 3
shot stage-building  -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 1e10 -yukikoro-crew 4,3 -yukikoro-gravity 5
shot stage-mountain  -yukikoro-demo -yukikoro-hour 17.7 -yukikoro-mass 2e12 -yukikoro-crew 4,3 -yukikoro-gravity 6
shot stage-range     -yukikoro-demo -yukikoro-hour 12   -yukikoro-mass 2e14 -yukikoro-crew 4,3 -yukikoro-gravity 6
shot early-pickup    -yukikoro-demo -yukikoro-hour 12   -yukikoro-mass 12 -yukikoro-crew 0,3
shot early-night     -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 300 -yukikoro-crew 0,5
shot plank-crew      -yukikoro-demo -yukikoro-hour 12   -yukikoro-mass 2500 -yukikoro-crew 2,3
shot stage-heli      -yukikoro-demo -yukikoro-hour 22   -yukikoro-mass 5e11 -yukikoro-crew 4,3 -yukikoro-gravity 4
DELAY=2.5 shot bh-squeeze  -yukikoro-demo -yukikoro-hour 22 -yukikoro-blackhole 0
DELAY=3.4 shot bh-flash    -yukikoro-demo -yukikoro-hour 22 -yukikoro-blackhole 0
DELAY=4.6 shot bh-shock    -yukikoro-demo -yukikoro-hour 22 -yukikoro-blackhole 0
DELAY=5.8 shot bh-ring     -yukikoro-demo -yukikoro-hour 22 -yukikoro-blackhole 0
DELAY=9   shot bh-card     -yukikoro-demo -yukikoro-hour 22 -yukikoro-blackhole 0
shot bh-after      -yukikoro-demo -yukikoro-hour 22 -yukikoro-blackhole 1
