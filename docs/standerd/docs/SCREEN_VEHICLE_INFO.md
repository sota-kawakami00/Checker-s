# SCREEN_VEHICLE_INFO.md — 車両情報入力画面

| 項目 | 内容 |
|---|---|
| ドキュメントID | SCR-VEHICLE |
| バージョン | v1.0 |
| 要件 | FR-201〜205 |
| 依存 | 03, 04(Vehicle), 06 §1.2 |

## 1. 画面目的

車検証OCRを起点に、査定に必要な車両情報を最短で正確に入力し、下書き（Appraisal draft）を作る。

## 2. UI構成

```
① OCRカード: [📷 車検証を撮影して自動入力] （結果反映後は「再撮影」）
② 基本情報フォーム
   メーカー ＞ 車種 ＞ グレード（段階Picker、マスタ配信 FR-202。OCR結果で事前選択）
   年式(初度登録) / 車台番号(下6桁マスク表示) / 走行距離(km, mono) / カラー / 車検満了日
③ 装備チェック: チップ複数選択（ナビ/ETC/サンルーフ/革シート/衝突軽減/両側電動…）
④ 下部固定: [撮影に進む]（必須項目充足で活性）
```

- 必須: メーカー/車種/年式/走行距離/カラー。他は任意（未入力は査定confidence低下要因としてAIへ渡る）。
- 全変更は即時下書き保存（FR-205）。戻る/強制終了で消えない。

## 3. 状態遷移

`empty → ocrScanning → ocrApplied(要確認ハイライト) → editing → valid → (撮影へ)`。OCR失敗は editing へフォールバック（手入力）。

## 4. ViewModel 責務（VehicleInfoViewModel）

- フォーム状態・バリデーション（走行距離0〜999,999、年式1970〜今年、満了日過去警告）
- `scanShaken()` → VehicleService.recognizeShaken → 各フィールドへ適用 + 適用フィールドをハイライト（誤OCR確認促し）
- マスタ段階ロード（maker選択→models取得→grade取得。キャッシュ24h）
- `proceedToCamera()` → appraisalService.createDraft/updateDraft → Route.camera

## 5. Service 責務

- VehicleService: OCR（Vision テキスト認識 + 車検証レイアウト規則でフィールド抽出）。マスタは Firestore `masters/vehicles` から取得しSwiftDataキャッシュ。
- AppraisalService.createDraft: Vehicle + Appraisal(status=draft, syncState=localOnly) 生成。

## 6. Firestore 更新

- なし（下書きはローカルのみ。SCREEN_CAMERA の submit で初同期）。マスタは読み取りのみ。

## 7. SwiftData キャッシュ

- Vehicle/Appraisal 下書き即時保存。マスタ（Maker/Model/Grade/Equipment）はキャッシュエンティティ+fetchedAt。

## 8. Geminiへ送るJSON

- `appraisal_request.schema.json` の `vehicle` オブジェクトの供給元。VINは下6桁マスク（07 §2.1）。未入力任意項目は null で送る（プロンプト側で「不明」として扱う指示済み）。

## 9. Vision Framework 処理

- VNRecognizeTextRequest（accurate, ja対応）→ 車検証テンプレートマッチで 車台番号/型式/初度登録/満了日 抽出。信頼度低フィールドは適用せず空+要入力ハイライト。

## 10. エラーハンドリング

- OCR不能（ブレ/非車検証）: 「読み取れませんでした。手入力してください」+フォームへ
- マスタ取得失敗: キャッシュがあれば継続+stale表示。なければ再試行導線（入力自体は自由テキスト代替不可＝メーカー等はマスタ必須のため撮影へは進めない旨表示）

## 11. アニメーション

- OCR適用フィールド: warning色ハイライト→2sでフェード
- Picker段階展開はデフォルト遷移。過剰演出なし（入力効率優先）

## 12. Liquid Glass デザインルール

- フォームは標準 grouped リスト+GlassCardセクション。入力中フィールドの視認性を優先しガラス効果は控えめ（bgBase基調）

## 13. アクセシビリティ

- 全フィールドにラベル/単位読み上げ（「走行距離、四万二千キロメートル」）
- 装備チップは isToggle トレイト。Dynamic Typeで折返しグリッド

## 14. テストケース

| ID | ケース | 期待 |
|---|---|---|
| SCR-VEH-01 | 正常車検証OCR | 4項目自動入力+ハイライト |
| SCR-VEH-02 | OCR低信頼フィールド | 未適用+要入力表示 |
| SCR-VEH-03 | 必須未充足 | 「撮影に進む」非活性 |
| SCR-VEH-04 | 入力途中で強制終了→再開 | 全値復元 |
| SCR-VEH-05 | 満了日が過去 | 警告表示（進行は可） |

## 15. Claude Code 実装指示

1. マスタ取得はモックJSONで先行実装（Firestore繋ぎ込みはM2後半）。
2. OCR抽出規則は `ShakenOCRParser` に分離し、車検証サンプル画像フィクスチャでUT。
3. バリデーションは ViewModel の pure function 化（`validate(form:) -> [FieldError]`）でテスト容易に。
