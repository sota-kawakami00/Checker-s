# SCREEN_HOME.md — ホーム画面

| 項目 | 内容 |
|---|---|
| ドキュメントID | SCR-HOME |
| バージョン | v1.0 |
| 要件 | UC-01起点, FR-504, FR-702(バナー) |
| 依存 | 03, 04, 06 |

## 1. 画面目的

「新規査定を最速で始める」ことと「進行中の査定に戻る」ことに特化した起点画面。

## 2. UI構成

```
① あいさつ + 店舗名 + 本日の査定数
② [＋ 新規査定] 大型PrimaryButton（画面上部・最優先）
③ 進行中カード横スクロール: 下書き/AI解析中/要確認(修復歴・低confidence)の査定
   各カード: 車両サムネ/車種/ステータスChip/経過時間。解析中はプログレス
④ 最近の確定 3件（→履歴へ）
⑤ タブバー: ホーム / 履歴 / ダッシュボード / 設定
⑥ OfflineBanner（オフライン時最上部固定、キュー件数表示）
```

## 3. 状態遷移

`loading(スケルトン) → content / empty(初回:イラスト+「最初の査定を始めましょう」)`。エラーはキャッシュ表示+再試行トースト。

## 4. ViewModel 責務（HomeViewModel）

- 進行中/最近確定の取得（SwiftDataクエリ、リアルタイム反映）
- 本日件数の集計（ローカル集計、ダッシュボードの厳密値とは別物と明記）
- `startNewAppraisal()` → Route.vehicleInfo(draftId: nil)
- キュー状態の購読（SyncService.queueStatus）→ バナー表示

## 5. Service 責務

- 読み取りのみ。AppraisalService.history(進行中フィルタ) + SyncService。

## 6. Firestore 更新

- なし（表示専用）。

## 7. SwiftData キャッシュ

- 全表示がキャッシュ起点。オフラインでも完全動作。

## 8. Geminiへ送るJSON

- なし。

## 9. Vision Framework 処理

- なし。

## 10. エラーハンドリング

- 同期エラーは OfflineBanner/トーストのみ。ホーム機能は停止させない。

## 11. アニメーション

- 解析中カードのプログレスリング。カード完了時に Chip がクロスフェード。

## 12. Liquid Glass デザインルール

- 進行中カードは GlassCard。新規査定ボタンは primary 塗り（ガラスにしない＝最重要CTA）。

## 13. アクセシビリティ

- 進行中カード: 「ヴォクシー、AI解析中、開始から2分」を1要素として読み上げ。

## 14. テストケース

| ID | ケース | 期待 |
|---|---|---|
| SCR-HOME-01 | 下書き2件+解析中1件 | ③に3枚、正しいChip |
| SCR-HOME-02 | 解析完了イベント | カードが要確認/確定待ちへ自動更新 |
| SCR-HOME-03 | 初回起動 | empty状態+CTA |
| SCR-HOME-04 | オフライン+キュー3件 | バナー「3件が同期待ち」 |

## 15. Claude Code 実装指示

1. M1で骨組み（モックデータ）→ M6でSyncバナー結線。
2. タブは `TabView` ルート。Route enum は NavigationStack 単位でタブ毎に保持。
