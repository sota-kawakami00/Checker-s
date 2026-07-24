# SCREEN_HISTORY.md — 査定履歴画面

| 項目 | 内容 |
|---|---|
| ドキュメントID | SCR-HISTORY |
| バージョン | v1.0 |
| 要件 | FR-601, FR-602, FR-504, NFR-03 |
| 依存 | 03, 04, 06 |

## 1. 画面目的

店舗の全査定を検索・追跡し、ステータス更新（成約/失注）と複製再査定の起点となる。

## 2. UI構成

```
① 検索バー（車種名/車台番号下桁）
② フィルタチップ: 期間 / ステータス / スタッフ / 修復歴あり
③ リスト（50件ページング, NFR-03）
   行: サムネ / 車種・年式 / 確定額(mono) / StatusChip / 日付 / 担当
   期限切れ間近(BR-05, 残2日)は warning ドット
④ 行スワイプ: [複製して再査定] [成約] [失注]
⑤ タップ → SCREEN_APPRAISAL_RESULT（閲覧モード）
```

## 3. 状態遷移

`loading → content / empty(フィルタ条件別文言) / error(キャッシュ表示+再試行)`。

## 4. ViewModel 責務（HistoryViewModel）

- フィルタ状態、デバウンス検索(300ms)、ページング制御（末尾到達で次50件）
- `duplicate(id)` → 新draft作成 → Route.vehicleInfo(draftId)
- `markWon/markLost(id)`（確定済みのみ可）

## 5. Service 責務

- AppraisalService.history(filter:page:): SwiftDataローカル検索を即時返却 + バックグラウンドでFirestore差分同期
- duplicate: Vehicle複製+新Appraisal(draft)。写真・AI結果は複製しない

## 6. Firestore 更新

- won/lost 更新（status + at + staffId）。オフライン時キュー。

## 7. SwiftData キャッシュ

- 一覧はローカルクエリが正。1000件でも1秒以内（インデックス: storeId+status+createdAt）。

## 8. Geminiへ送るJSON / 9. Vision

- なし。

## 10. エラーハンドリング

- 同期失敗はトーストのみ、ローカル結果は常時表示。

## 11. アニメーション

- ステータス変更時の Chip クロスフェード。スワイプアクション標準。

## 12. Liquid Glass デザインルール

- リストは標準リスト（大量表示のためガラス効果なし）。フィルタバーのみ glass。

## 13. アクセシビリティ

- 行を1要素で要約読み上げ。スワイプ操作は Rotor アクションでも提供。

## 14. テストケース

| ID | ケース | 期待 |
|---|---|---|
| SCR-HIS-01 | 1000件+ステータスフィルタ | 1秒以内表示・正しい絞込 |
| SCR-HIS-02 | 複製 | 車両情報のみ引継ぎ・写真なし draft |
| SCR-HIS-03 | 成約マーク（オフライン） | 即時反映+キュー |
| SCR-HIS-04 | 期限残2日 | warning ドット表示 |

## 15. Claude Code 実装指示

1. 検索・フィルタは `HistoryFilter` struct + SwiftData Predicate 生成関数に集約しUT。
2. ページングは `@Query` ではなく明示 fetch（オフセット制御のため）。
