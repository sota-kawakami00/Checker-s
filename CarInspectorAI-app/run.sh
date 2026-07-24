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
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator

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
echo "✅ CarInspectorAI を起動しました ($SIM_NAME)"
