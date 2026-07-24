# AGENTS.md — AIエージェント共通ルール

Claude Code 以外のAIコーディングエージェント（Codex, Cursor, Devin 等）も本ファイルに従うこと。
Claude Code 固有の詳細は `CLAUDE.md` を参照。矛盾時は `CLAUDE.md` が優先。

## 共通原則

1. **Docs First**: 設計書にない仕様を実装しない。設計変更が必要なら、まず docs を更新する提案を行う。
2. **Schema is Law**: `schemas/*.schema.json` は入出力の唯一の契約。フィールド追加・削除・型変更は破壊的変更。
3. **1タスク1責務**: 依頼されたタスクの範囲外のリファクタリングを勝手に行わない。気づいた改善点は報告のみ。
4. **テスト同時実装**: 実装コードとテストコードは同一タスクで書く。テストなしのマージは不可。
5. **秘密情報の非ハードコード**: APIキーは `Config.xcconfig`（gitignore対象）+ Info.plist 経由。コードに書かない。

## ビルド・検証コマンド

```bash
# ビルド
xcodebuild -scheme CarInspectorAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# ユニットテスト
xcodebuild -scheme CarInspectorAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# SwiftLint（設定: .swiftlint.yml）
swiftlint --strict

# schema検証（examples が schema に適合するか）
npx ajv-cli validate -s schemas/appraisal_result.schema.json -d examples/appraisal_result.example.json
```

## コードスタイル

- Swift 6 / Strict Concurrency Checking = Complete
- インデント: スペース4
- 1ファイル400行を超えたら分割を検討
- コメントは「なぜ」を書く。「何を」はコードで表現
- ドキュメントコメント（`///`）は public な Service protocol と ViewModel の公開メソッドに必須

## ブランチ・コミット

- ブランチ: `feature/screen-camera`, `fix/appraisal-retry` 形式
- コミット: Conventional Commits（`feat:` `fix:` `docs:` `test:` `refactor:`）
- main への直接 push 禁止

## レビュー観点（セルフチェックリスト）

- [ ] 対応する SCREEN_*.md / docs の要求を全て満たしているか
- [ ] `CLAUDE.md` §2.3 の禁止事項に触れていないか
- [ ] エラー時のユーザー体験（オフライン・タイムアウト・権限拒否）を実装したか
- [ ] アクセシビリティ（VoiceOver ラベル、Dynamic Type）を実装したか
- [ ] 個人情報のマスキング処理を通しているか（画像送信系）
