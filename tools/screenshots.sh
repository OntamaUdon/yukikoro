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
  sleep "${DELAY:-10}"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  xcrun simctl terminate "$UDID" "$BUNDLE" || true
}

# 画面確認用の起動引数（DEBUG のみ）: -yukikoro-demo -yukikoro-steps N -yukikoro-tab N -yukikoro-sheet tower|carry
shot map          -yukikoro-demo -yukikoro-steps 3000
# 起動に失敗したときの手がかり（落ちていれば、ここに出る）
xcrun simctl spawn "$UDID" log show --style compact --last 2m --predicate 'process == "Yukikoro"' 2>/dev/null | grep -iE "fatal|crash|exception|terminat|error" | head -20 || true
ls ~/Library/Logs/DiagnosticReports 2>/dev/null | head -5 || true
shot map-big      -yukikoro-demo -yukikoro-steps 40000
shot tower        -yukikoro-demo -yukikoro-steps 3000 -yukikoro-sheet tower
shot carry        -yukikoro-demo -yukikoro-steps 12000 -yukikoro-sheet carry
shot ranking      -yukikoro-demo -yukikoro-tab 1
shot record       -yukikoro-demo -yukikoro-tab 2
shot settings     -yukikoro-demo -yukikoro-tab 3
shot onboarding
