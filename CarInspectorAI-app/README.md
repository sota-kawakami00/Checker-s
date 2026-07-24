# CarInspectorAI — 実装リポジトリ

`docs/standerd/`（設計書一式 v1.0）に基づく **AI中古車査定OS** の iOS 実装です。
設計書の実装ルール（`CLAUDE.md` / `AGENTS.md`）に従い、MVVM + Service層・Offline First・Schema Driven で構築しています。

## 構成（00_PROJECT_OVERVIEW §8 準拠）

```
CarInspectorAI-app/
├── project.yml               # XcodeGen 定義（CarInspectorAI.xcodeproj を生成）
├── CarInspectorAI/           # アプリターゲット
│   ├── App/                  # エントリポイント, AppContainer(DI), Route, 認証/アプリロックゲート
│   ├── Features/             # Home / VehicleInfo / Camera / AppraisalResult / History / Dashboard / Settings
│   └── Resources/            # Assets, Localizable.xcstrings（日本語ベース）
├── Packages/
│   ├── Core/                 # AppError, SwiftDataモデル, 共通型
│   ├── DesignSystem/         # デザイントークン(03準拠), GlassCard/PriceLabel等の共通部品
│   ├── AppraisalKit/         # 査定ドメイン: Service, schema準拠Codable, Validator, PDF, 集計
│   ├── CameraKit/            # 品質判定(05§2), マスキング(07§2), カメラセッション, ガイド枠
│   └── SyncKit/              # オフラインキュー(02§5), RemoteBackend抽象, Mapper, 認証
├── functions/                # Cloud Functions (TypeScript): runAppraisal / fetchMarketPrice 等
├── CarInspectorAITests/      # ViewModel・結合フロー（UC-01/02ロジック）テスト
└── CarInspectorAIUITests/    # UI-01（UC-01完走）XCUITest
```

## 実行（ワンコマンド）

```bash
./run.sh                  # ビルド→シミュレータ起動→インストール→起動（ログイン画面から）
./run.sh --uitest-signin  # デモスタッフで自動ログインして起動
```

## セットアップ・検証コマンド

```bash
# プロジェクト生成（要 xcodegen）
xcodegen generate

# ビルド（AGENTS.md）
xcodebuild -scheme CarInspectorAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# ユニット+UIテスト
xcodebuild -scheme CarInspectorAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# パッケージ単体テスト（macOSで高速実行可能）
for p in Core DesignSystem AppraisalKit CameraKit SyncKit; do (cd Packages/$p && swift test); done

# Cloud Functions
cd functions && npm install && npm run build && npm test
```

デモアカウント: `staff@carinspector.jp` / `manager@carinspector.jp`（パスワード `demo1234`）
シミュレータではモックカメラ（合成車両画像）で撮影フローが完走します。表示言語は日本語端末を想定しています。

## テストトレース（08_TEST_PLAN → 実装）

| 設計書テストID | 実装 |
|---|---|
| UT-BR01/BR02系（価格整合） | `AppraisalKitTests/AppraisalResultValidatorTests` + `functions/test/appraisalResultValidator` |
| UT-BR03 / UT-UC03 / UT-FR407（確定ガード） | `AppraisalKitTests/AppraisalConfirmTests` |
| UT-SYNC-01〜06（オフラインキュー） | `SyncKitTests/SyncQueueTests` |
| UT-PQ-01〜03（品質フィクスチャ） | `CameraKitTests/QualityAnalyzerTests`（合成画像フィクスチャ） |
| UT-MASK-01〜03（マスキング/EXIF） | `CameraKitTests/MaskingPipelineTests` |
| SCR-VEH / SCR-CAM / SCR-RES / SCR-HOME / SCR-HIS / SCR-DASH | 各パッケージ・`CarInspectorAITests` |
| CF: 冪等性 / quota / precondition / キャッシュ / examples×schema適合 | `functions/test/`（vitest + ajv, 75件） |
| UI-01（UC-01完走: 入力→12枚撮影→AI→確定→PDF） | `CarInspectorAIUITests/UC01FlowUITests` |
| UC-02（オフライン→復帰→自動実行） | `CarInspectorAITests/HomeAndFlowTests.uc02OfflineFlow` |

## Firebase / Gemini 接続について（重要）

本リポジトリには Firebase プロジェクト設定・APIキーを**含めていません**（07_SECURITY: 秘密情報の非ハードコード）。
現状はアーキテクチャ上の差し替え点を protocol で確保した**ローカル完結構成**で全機能が動作します。

- `SyncKit.RemoteBackend` … Firestore/Storage/CF 抽象。現在は `InMemoryRemoteBackend`（CF runAppraisal を模擬。
  BR-01/02 を満たす結果を examples ベースの「録画リプレイ方式」(08§1) で生成）。
- `Core.AuthService` … 現在は `MockAuthService`（デモアカウント）。
- 本番結線手順: (1) `GoogleService-Info.plist` をCIで注入 (2) firebase-ios-sdk を追加し
  `FirebaseRemoteBackend: RemoteBackend` / `FirebaseAuthService: AuthService` を実装
  (3) `AppContainer.production()` の生成箇所を差し替え (4) `functions/` を `firebase deploy`
  （Secret Manager に `GEMINI_API_KEY` / `MARKET_API_KEY` を登録、05§8/07§6）。

## 設計書からの逸脱・判断メモ（Docs First: 設計書への追補提案）

1. **`AppError.validation(reason:)` を追加**（02 §6 追補提案）。FR-407 の「バリデーションエラー」等、
   入力検証エラーの表現が既定ケースに無かったため。
2. **`VehicleService.recognizeShaken(from: CGImage)`**（06 §1.2 は UIImage）。パッケージの
   クロスプラットフォームテスト（macOSでのVision実行）を可能にするため。
3. **`PhotoService.persist` に `memo`/`quality` 引数を追加**（06 §1.3）。SCREEN_CAMERA の
   ダメージメモ・品質結果記録（04 PhotoAsset.qualityResultJSON）を1トランザクションで満たすため。
4. **車両BBox検出は Vision の物体顕著性（saliency）で近似**。設計書記載の
   `VNRecognizeObjectsRequest（車両クラス）` は実在しないAPIのため。専用CoreMLモデルへ
   差し替え可能なよう `VehicleDetecting` protocol 化。
5. **パッケージ内文言は `ja.lproj/Localizable.strings`**。SwiftPM CLI ビルドが xcstrings を
   コンパイルしないため（アプリ本体は xcstrings）。v1は日本語のみ（NFR-11）で、非日本語端末でも
   ja へフォールバックする。
6. **プロジェクト生成に XcodeGen を採用**（.xcodeproj をコミットせず project.yml を正とする）。
7. スタッフ招待（FR-104）の CF 結線・クラウド二次品質判定（checkPhotoQuality の呼び出し側）・
   出品票比較（FR-409, Phase 2）は設計書の指示どおりスタブ/設計先行。
8. 相場プロバイダ（functions）は契約前のため `UnconfiguredMarketPriceProvider`
  （常時キャッシュ/staleフォールバックの安全動作）。

## マイルストーン対応（09_ROADMAP）

M1 基盤 / M2 入力+OCR / M3 撮影+品質AI+マスキング / M4 AIパイプライン(CF) / M5 結果+確定 /
M6 同期キュー / M7 PDF / M8 履歴・ダッシュボード・設定 — **Phase 1 実装済み**。
M9（実機・屋外の手動チェックリスト、Firebase実結線後の統合テスト）は実環境が必要なため未実施。
