# CarInspectorAI 設計書一式 v1.0

**AI中古車査定OS — 設計ドキュメントリポジトリ**

本リポジトリは、iOSアプリ「CarInspectorAI」をClaude Code等のAIコーディングエージェントで実装するための、完全な設計書一式です。

## このリポジトリの使い方

1. **人間の開発者・PM**: `docs/00_PROJECT_OVERVIEW.md` から読み始めてください。
2. **Claude Code / AIエージェント**: まず `CLAUDE.md` と `AGENTS.md` を読み、実装対象の画面・機能に対応する `docs/SCREEN_*.md` / `docs/*.md` を参照してください。
3. **プロンプト・スキーマ**: Gemini API へ送るプロンプトは `prompts/`、入出力JSONの契約は `schemas/` に定義されています。**実装時はこの契約を唯一の正とします。**

## ディレクトリ構成

```
CarInspectorAI/
├── README.md                     # 本ファイル
├── CLAUDE.md                     # Claude Codeへの最上位指示（必読）
├── AGENTS.md                     # AIエージェント共通ルール
├── docs/
│   ├── 00_PROJECT_OVERVIEW.md    # システム概要・技術スタック・方針
│   ├── 01_REQUIREMENTS.md        # 機能要件・非機能要件
│   ├── 02_SYSTEM_ARCHITECTURE.md # アーキテクチャ詳細
│   ├── 03_UI_UX_GUIDELINE.md     # Liquid Glassデザインシステム
│   ├── 04_DATA_MODEL.md          # SwiftData / Firestore データモデル
│   ├── 05_AI_PIPELINE.md         # AI査定パイプライン全体設計
│   ├── 06_API_DESIGN.md          # 外部API・内部Service層設計
│   ├── 07_SECURITY.md            # セキュリティ・認証・データ保護
│   ├── 08_TEST_PLAN.md           # テスト戦略・テストケース
│   ├── 09_ROADMAP.md             # フェーズ計画・将来拡張
│   ├── SCREEN_HOME.md            # ホーム画面
│   ├── SCREEN_CAMERA.md          # 撮影画面（最重要・最詳細）
│   ├── SCREEN_VEHICLE_INFO.md    # 車両情報入力画面
│   ├── SCREEN_APPRAISAL_RESULT.md# 査定結果画面
│   ├── SCREEN_HISTORY.md         # 査定履歴画面
│   ├── SCREEN_DASHBOARD.md       # 店舗ダッシュボード画面
│   └── SCREEN_SETTINGS.md        # 設定画面
├── prompts/
│   ├── appraisal_main.md         # メイン査定プロンプト
│   ├── photo_quality.md          # 写真品質判定プロンプト
│   ├── repair_history.md         # 修復歴推定プロンプト
│   ├── auction_sheet_ocr.md      # オークション出品票OCR・比較プロンプト
│   └── completeness_check.md     # 査定漏れ診断プロンプト
├── schemas/
│   ├── appraisal_request.schema.json
│   ├── appraisal_result.schema.json
│   ├── photo_quality.schema.json
│   ├── repair_history.schema.json
│   ├── auction_comparison.schema.json
│   ├── completeness.schema.json
│   └── firestore_collections.md  # Firestoreコレクション定義
├── examples/
│   ├── appraisal_result.example.json
│   ├── photo_quality.example.json
│   └── repair_history.example.json
├── diagrams/
│   └── （Mermaid図は各docs内に埋め込み。書き出し先）
└── assets/
    └── （デザイントークン・アイコン定義の置き場）
```

## バージョン

- 設計書バージョン: **v1.0**
- 対象プラットフォーム: iOS 18+ / iPadOS 18+
- 想定実装ツール: Claude Code（他のAIエージェントも可）

## 変更管理ルール

- 設計変更は必ず該当Markdownを更新してからコードを変更する（**Docs First**）
- スキーマ（`schemas/`）の変更は破壊的変更として扱い、`09_ROADMAP.md` の変更履歴に記録する
