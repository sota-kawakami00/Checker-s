# 09_ROADMAP.md — ロードマップ・変更履歴

| 項目 | 内容 |
|---|---|
| ドキュメントID | DOC-09 |
| バージョン | v1.0 |

---

## Phase 1 — MVP（実装順は CLAUDE.md §4）

**ゴール**: 1店舗で実務投入できる査定OS。UC-01/02/03 が完走する。

| マイルストーン | 内容 | 完了条件 |
|---|---|---|
| M1 基盤 | AppContainer/ルーティング/DesignSystem/SwiftDataスタック | mock環境で全画面骨組み遷移 |
| M2 入力 | SCREEN_VEHICLE_INFO + 車検証OCR + マスタ配信 | FR-201〜205 テスト green |
| M3 撮影 | SCREEN_CAMERA + 品質AI一次 + マスキング | FR-301〜306 / UT-PQ/UT-MASK green |
| M4 AI | CF runAppraisal + fetchMarketPrice + 検証 | 契約テスト・BR-02系 green |
| M5 結果 | SCREEN_APPRAISAL_RESULT + 確定フロー + 修復歴UI | UC-01/03 UIテスト green |
| M6 同期 | SyncKit オフラインキュー完成 | UC-02 / UT-SYNC green |
| M7 出力 | PDF生成・共有 | FR-502/503 |
| M8 管理 | HISTORY / DASHBOARD / SETTINGS | FR-6xx/7xx |
| M9 硬化 | 性能・a11y・セキュリティ監査、手動チェックリスト | §08 全ゲート通過 |

## Phase 2

- OBD-II診断連携（ELM327 Bluetooth）: 診断コードを減点根拠に統合（FR-410）
- オークション出品票OCR比較（FR-409）: `generateAuctionComparison` 実装
- 査定書テンプレートカスタマイズ（店舗ロゴ・項目編集）
- クラウド品質判定（checkPhotoQuality）の本格運用とアングル適合判定
- プロンプトA/B運用基盤

## Phase 3

- 本部向け複数店舗横断ダッシュボード
- 相場トレンド予測（時系列モデル）
- 顧客同意ベースの査定結果共有リンク
- Android / Web 検討

## 変更履歴（Schema/Docs 破壊的変更はここに必ず記録）

| 日付 | 版 | 変更 |
|---|---|---|
| 2026-07-21 | v1.0 | 初版一式作成 |
