# SCREEN_DASHBOARD.md — 店舗ダッシュボード画面

| 項目 | 内容 |
|---|---|
| ドキュメントID | SCR-DASH |
| バージョン | v1.0 |
| 要件 | FR-603, FR-604, 認可(06 §4) |
| 依存 | 03, 04, 06 |

## 1. 画面目的

店長/マネージャーが査定→成約ファネルとスタッフ実績を把握し、AI査定と人の調整の乖離から運用改善の示唆を得る。

## 2. UI構成

```
① 期間セグメント: 今日 / 今週 / 今月 / カスタム
② KPIカード4枚: 査定件数 / 確定率 / 成約率 / 平均査定額（前期間比 ▲▼%）
③ 推移チャート: 件数+成約の複合（Swift Charts, 日別）
④ スタッフ別テーブル: 件数/確定/成約/平均調整幅（managerのみ全員、staffは自分のみ 06§4）
⑤ AI乖離カード(FR-604, manager+): AI提案と確定額の平均乖離・乖離大の査定リスト→詳細へ
```

## 3. 状態遷移

`loading(スケルトンKPI) → content / empty(期間内0件) / error(前回キャッシュ+stale表示)`。

## 4. ViewModel 責務（DashboardViewModel）

- 期間状態、DashboardService 呼び出し、権限による④⑤の出し分け（currentStaff.role）

## 5. Service 責務

- DashboardService: 集計はローカルSwiftData集計（確定値はFirestore同期後に一致）。乖離分析は `(confirmedPrice - aiProposedPrice)` の統計。
- 将来（Phase 3）はCF事前集計へ差し替え可能な interface を維持。

## 6. Firestore 更新

- なし（読み取りのみ）。

## 7. SwiftData キャッシュ

- 集計はローカル実行。最終同期時刻を表示（「〜時点」）。

## 8. Gemini / 9. Vision

- なし。

## 10. エラーハンドリング

- 集計失敗時は各カード単位でエラー表示（画面全体を落とさない）。

## 11. アニメーション

- KPI数値カウントアップ（初回のみ）。チャートは Swift Charts 標準トランジション。

## 12. Liquid Glass デザインルール

- KPIカードは GlassCard。チャート背景は bgBase（可読性）。

## 13. アクセシビリティ

- チャートに audio graph（Swift Charts標準）+ サマリテキスト代替。

## 14. テストケース

| ID | ケース | 期待 |
|---|---|---|
| SCR-DASH-01 | staff ロール | ④が自分のみ・⑤非表示 |
| SCR-DASH-02 | 期間切替 | KPI/チャート再計算 |
| SCR-DASH-03 | 0件期間 | empty 表示 |
| SCR-DASH-04 | 乖離計算 | 符号・平均値が期待どおり（フィクスチャ） |

## 15. Claude Code 実装指示

1. 集計ロジックは `DashboardCalculator`（pure）に分離しUT先行。
2. 権限出し分けは View ではなく ViewModel の公開プロパティで制御。
