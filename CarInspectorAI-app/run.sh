#!/bin/bash
# CarInspectorAI をシミュレータで自動実行する
#   ./run.sh                 … 通常起動（ログイン画面。デモ: staff@carinspector.jp / demo1234）
#   ./run.sh --uitest-signin … デモスタッフで自動ログインして起動
#   SIM_NAME="iPad Pro 11-inch (M4)" ./run.sh … 端末指定
set -euo pipefail
cd "$(dirname "$0")"

SIM_NAME="${SIM_NAME:-iPhone 16 Pro}"
BUNDLE_ID="com.animetourism.carinspector"

# 1) プロジェクト生成（project.yml が正）
if ! command -v xcodegen >/dev/null; then
  echo "xcodegen が必要です: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate --quiet

# 2) シミュレータ特定・起動
UDID=$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
if [ -z "$UDID" ]; then
  echo "シミュレータ '$SIM_NAME' が見つかりません" >&2
  exit 1
fi
# 対象以外の起動中デバイスを落とし、目的のウィンドウだけが前面に出るようにする
for booted in $(xcrun simctl list devices | grep Booted | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'); do
  if [ "$booted" != "$UDID" ]; then
    xcrun simctl shutdown "$booted" >/dev/null 2>&1 || true
  fi
done
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID"

# 3) ビルド
echo "▸ ビルド中 ($SIM_NAME)…"
xcodebuild -project CarInspectorAI.xcodeproj -scheme CarInspectorAI \
  -destination "id=$UDID" build -quiet

# 4) ビルド成果物のパスを解決してインストール・起動
BUILD_DIR=$(xcodebuild -project CarInspectorAI.xcodeproj -scheme CarInspectorAI \
  -destination "id=$UDID" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2; exit}')
APP="$BUILD_DIR/CarInspectorAI.app"

xcrun simctl install "$UDID" "$APP"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" "$@" >/dev/null

# Simulator ウィンドウを前面へ
osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1 || true

# 起動確認（プロセスが立ち上がっているかを検証）
sleep 2
RUNNING=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)
if echo "$RUNNING" | grep -q "$BUNDLE_ID"; then
  echo "✅ CarInspectorAI を起動しました ($SIM_NAME)。Simulator のウィンドウをご確認ください。"
else
  echo "⚠️ 起動を確認できませんでした。もう一度 ./run.sh を実行してください。" >&2
  exit 1
fi
