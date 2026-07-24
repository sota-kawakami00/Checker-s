#!/bin/bash
# CarInspectorAI を TestFlight へ配信する
#
#   ./testflight.sh            … アーカイブ + ipa 書き出しまで（アップロードは Xcode Organizer / Transporter で）
#   ./testflight.sh --upload   … App Store Connect API キーで自動アップロードまで実行
#
# 自動アップロードに必要な環境変数（App Store Connect > ユーザとアクセス > 統合 > App Store Connect API で作成）:
#   ASC_KEY_ID     … キーID（例 ABC123XYZ）
#   ASC_ISSUER_ID  … Issuer ID（UUID形式）
#   ASC_KEY_PATH   … AuthKey_XXXX.p8 のパス（既定: ./private_keys/AuthKey_${ASC_KEY_ID}.p8）
#
# 事前に App Store Connect で「マイアプリ > +」から
# Bundle ID com.animetourism.carinspector のアプリを1度だけ作成しておくこと。
set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="DXWDABVY8M"
ARCHIVE_PATH="build/CarInspectorAI.xcarchive"
EXPORT_PATH="build/export"

xcodegen generate --quiet
mkdir -p build

# ビルド番号を自動インクリメント（TestFlight は同一ビルド番号を受け付けないため）
BUILD_NUMBER=$(date +%Y%m%d%H%M)
echo "▸ アーカイブ中… (build $BUILD_NUMBER)"
xcodebuild -project CarInspectorAI.xcodeproj -scheme CarInspectorAI \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive -quiet

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "▸ ipa 書き出し中…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates -quiet

IPA=$(ls "$EXPORT_PATH"/*.ipa | head -1)
echo "✅ ipa: $IPA"

if [ "${1:-}" != "--upload" ]; then
  echo ""
  echo "アップロード方法:"
  echo "  A) 自動: ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH を設定して ./testflight.sh --upload"
  echo "  B) 手動: Transporter.app（App Store）に上記 ipa をドラッグ&ドロップ"
  echo "  C) 手動: Xcode > Window > Organizer から ${ARCHIVE_PATH} を Distribute App"
  exit 0
fi

: "${ASC_KEY_ID:?ASC_KEY_ID が未設定です}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID が未設定です}"
ASC_KEY_PATH="${ASC_KEY_PATH:-./private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$ASC_KEY_PATH" ] || { echo "APIキーが見つかりません: $ASC_KEY_PATH" >&2; exit 1; }

echo "▸ App Store Connect へアップロード中…"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "✅ アップロード完了。App Store Connect > TestFlight で処理完了（数分〜十数分）を待ってください。"
