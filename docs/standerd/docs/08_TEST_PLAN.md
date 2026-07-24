# 08_TEST_PLAN.md — テスト計画

| 項目 | 内容 |
|---|---|
| ドキュメントID | DOC-08 |
| バージョン | v1.0 |
| 依存 | 全ドキュメント（要件IDでトレース） |

---

## 1. テスト戦略

| レベル | 対象 | ツール | カバレッジ目標 |
|---|---|---|---|
| ユニット | Service, ViewModel, Mapper, 検証ロジック | Swift Testing | 70%+（NFR-09） |
| スキーマ | schemas/ と examples/ の適合、CF検証ロジック | ajv + vitest | examples全件 |
| 統合 | SyncKit（SwiftData⇔Firestoreエミュレータ）, CF | Firebase Emulator Suite | 主要フロー |
| UI | 主要5フロー | XCUITest | UC-01〜03 |
| 手動 | 実車・屋外撮影、実機性能 | チェックリスト（§5） | リリース毎 |

- ViewModel テストは `AppContainer.mock()` のモックServiceで実施。ネットワーク到達禁止。
- AI出力は**録画リプレイ方式**: examples/ の固定JSONをモックGeminiが返す。実API呼び出しテストはCF側の契約テストのみ（日次1回）。

## 2. ユニットテスト重点ケース

### 2.1 価格整合（BR-01/BR-02）— `AppraisalResultValidatorTests`

| ID | ケース | 期待 |
|---|---|---|
| UT-BR02-01 | base 1,800,000 + (+50k+30k-40k-20k-10k) = 1,810,000 | 検証OK |
| UT-BR02-02 | 内訳合計と価格が1円でも不一致 | `aiInvalidResponse` |
| UT-BR01-01 | 1,813,000円（万未満端数） | CF側丸め検証NG（万単位でない） |
| UT-BR02-03 | adjustments空 + base==price | 検証OK |
| UT-BR02-04 | evidencePhotoId が存在しないIDを参照 | `aiInvalidResponse` |

### 2.2 確定ガード（BR-03/UC-03）— `AppraisalConfirmTests`

| ID | ケース | 期待 |
|---|---|---|
| UT-BR03-01 | confidence 0.59 で staff が confirm | `forbidden`（manager承認導線） |
| UT-BR03-02 | confidence 0.59 で manager が confirm | 成功 + adjustmentLog記録 |
| UT-UC03-01 | repairProbability 0.6, repairConfirmedState == none で confirm | ブロック |
| UT-UC03-02 | 修復歴「あり」確定 | 再査定リクエストが発行される（BR-04） |
| UT-FR407-01 | AI提案額と異なる額で確定・理由なし | バリデーションエラー |

### 2.3 オフラインキュー（NFR-04/05）— `SyncQueueTests`

| ID | ケース | 期待 |
|---|---|---|
| UT-SYNC-01 | オフラインで requestAIAppraisal | SyncTask登録、状態 pendingUpload |
| UT-SYNC-02 | 復帰イベント | 60秒以内にキュー実行開始、順序は createdAt 昇順 |
| UT-SYNC-03 | 同一appraisalIdのタスク | 直列実行される |
| UT-SYNC-04 | 3回連続失敗 | state failed、FR-702のUIに露出 |
| UT-SYNC-05 | 画像アップ未完で runAppraisal | 前提条件エラー→画像完了後に自動再試行 |
| UT-SYNC-06 | サーバー競合 | サーバー版採用 + ローカル退避コピー生成 |

### 2.4 写真品質・マスキング — `PhotoPipelineTests`

| ID | ケース | 期待 |
|---|---|---|
| UT-PQ-01 | ブレ画像フィクスチャ | focus NG + 指定メッセージ |
| UT-PQ-02 | 低輝度フィクスチャ | brightness NG |
| UT-PQ-03 | 車両見切れフィクスチャ（front） | framing NG「下がって撮影」 |
| UT-MASK-01 | ナンバー写り画像 | マスク済画像のナンバー領域が判読不能 |
| UT-MASK-02 | EXIF GPS付き画像 | 出力にEXIF/GPSなし |
| UT-MASK-03 | 検出失敗画像 | maskVerified=false で記録、手動マスク導線 |

## 3. スキーマ・CFテスト（functions/）

- `examples/*.example.json` が対応する schema に**全件適合**すること（CIゲート）
- runAppraisal: 冪等性（同一requestId 2連投で1回のみ実行）/ quota超過 / 画像未完 precondition
- fetchMarketPrice: キャッシュヒット・stale応答・プロバイダ障害フォールバック

## 4. UIテスト（XCUITest）

| ID | シナリオ |
|---|---|
| UI-01 | UC-01完走: 新規査定→OCR→12枚撮影(モック)→AI査定(モック)→確定→PDF生成 |
| UI-02 | UC-02: 機内モードで撮影完了→復帰→自動査定→結果表示 |
| UI-03 | UC-03: 修復歴警告→未確認で確定不可→確認後確定 |
| UI-04 | 品質NG→再撮影トースト表示→再撮影で解消 |
| UI-05 | 履歴検索・複製再査定 |

## 5. 手動テストチェックリスト（リリース毎）

- [ ] 直射日光下で価格・トーストが読める（実機・屋外）
- [ ] 逆光/夕方/屋内暗所での品質判定の妥当性（各10枚）
- [ ] iPhone 13（最低スペック）でNFR-01/02/03を満たす
- [ ] Dynamic Type xxxLarge で全画面崩れなし
- [ ] VoiceOverで UC-01 が完走できる
- [ ] 機内モード→復帰→データ消失ゼロ
- [ ] Face IDロック・パスワードリセット動線

## 6. 性能テスト

- 品質判定 p95 <= 1.5s / AI査定 p95 <= 60s / 履歴1000件初期表示 <= 1s を、計測コード（signpost）+ Performance Monitoring で継続監視。閾値超過はリリースブロッカー。
