# CLAUDE.md — Claude Code 最上位指示書

このファイルは CarInspectorAI を実装する Claude Code への**最上位の指示**です。
他のドキュメントと矛盾がある場合、優先順位は以下の通りです。

```
CLAUDE.md > AGENTS.md > schemas/ > docs/SCREEN_*.md > docs/00〜09 > prompts/
```

---

## 1. プロジェクト概要（1分で理解する）

- **何を作るか**: 中古車販売店スタッフ向けの iOS 査定アプリ。車両を撮影し、AI（Gemini）が査定価格・根拠・修復歴の可能性まで提示する。
- **本質**: 単発の査定ツールではなく「AI中古車査定OS」。査定 → PDF出力 → 店舗管理 → ダッシュボードまでを1つのプラットフォームとして設計している。
- **技術**: SwiftUI + MVVM / SwiftData（ローカルキャッシュ）/ Firestore(クラウド) / Vision Framework(端末内前処理) / Gemini API(査定推論)。

## 2. 絶対に守る実装ルール

### 2.1 アーキテクチャ原則

1. **MVVM + Service層**。View → ViewModel → Service → (Firestore / Gemini / SwiftData) の一方向依存。逆流禁止。
2. View に業務ロジックを書かない。View は状態の描画とユーザー操作のViewModelへの委譲のみ。
3. ViewModel は `@Observable`（Observation framework）を使用。`ObservableObject` + `@Published` は使わない。
4. Service は protocol で抽象化し、ViewModel には protocol 型で注入する（テスト時にモック差し替え可能にする）。
5. 非同期処理は **async/await のみ**。Combine・コールバックは新規に書かない。
6. Firestore への書き込みは必ず Service 層経由。View / ViewModel から直接 SDK を呼ばない。

### 2.2 命名規則

| 対象 | 規則 | 例 |
|---|---|---|
| View | `〜View` | `CameraView`, `AppraisalResultView` |
| ViewModel | `〜ViewModel` | `CameraViewModel` |
| Service protocol | `〜Service` | `AppraisalService` |
| Service 実装 | `〜ServiceImpl` | `AppraisalServiceImpl` |
| SwiftData モデル | 単数名詞 | `Vehicle`, `Appraisal`, `PhotoAsset` |
| Firestore DTO | `〜DTO` | `AppraisalDTO` |
| Gemini入出力 | `Gemini〜Request/Response` | `GeminiAppraisalRequest` |
| Enum case | lowerCamelCase | `.frontLeft`, `.repairSuspected` |
| ファイル名 | 型名と一致 | `CameraViewModel.swift` |

### 2.3 禁止事項

- ❌ 強制アンラップ（`!`）。`guard let` / `??` を使う。ただし `@IBOutlet` 相当は存在しない（SwiftUIのみ）ため例外なし。
- ❌ `DispatchQueue.main.async`。`@MainActor` を使う。
- ❌ シングルトンの新規作成（`FirebaseApp` 等SDK側は除く）。DIコンテナ（`AppContainer`）経由で注入。
- ❌ ハードコードされた文字列UI。`Localizable.xcstrings` に定義（日本語ベース）。
- ❌ ハードコードされた色・余白。`docs/03_UI_UX_GUIDELINE.md` のデザイントークンを使う。
- ❌ Gemini へのリクエスト/レスポンスの独自解釈。`schemas/*.schema.json` が唯一の契約。
- ❌ 査定価格ロジックのクライアント側再実装。価格計算は Gemini 出力 + `AppraisalService` の後処理のみ。
- ❌ 個人情報（顧客名・ナンバープレート生画像）の端末外送信。送信前にマスキング処理必須（`07_SECURITY.md`）。

### 2.4 エラーハンドリング

- 全 Service は `AppError`（`docs/02_SYSTEM_ARCHITECTURE.md` §6 定義）を throw する。
- ネットワークエラーは自動リトライ（指数バックオフ、最大3回）。それでも失敗したら「オフラインキュー」（SwiftData）に保存し、復帰時に再送。
- ユーザー向けエラーメッセージは技術詳細を出さない。「通信に失敗しました。査定データは保存されています。」の粒度。

## 3. 実装の進め方

1. 実装前に対象画面の `docs/SCREEN_*.md` を**全文読む**。
2. 依存する schema / prompt を確認する。
3. Service → ViewModel → View の順で実装する（内側から外側へ）。
4. 各層のユニットテストを `08_TEST_PLAN.md` のケース表に従って書く。
5. 1画面 = 1 PR 相当の粒度でコミットを分ける。コミットメッセージは日本語可、`feat: カメラ画面のガイド枠オーバーレイを実装` の形式。

## 4. 実装優先順位（Phase 1 MVP）

```
1. AppContainer / ルーティング / デザイントークン
2. SCREEN_VEHICLE_INFO（車両情報入力）
3. SCREEN_CAMERA（撮影 + 写真品質AI）
4. AI パイプライン（AppraisalService + Gemini連携）
5. SCREEN_APPRAISAL_RESULT（査定結果 + 根拠可視化）
6. SCREEN_HISTORY / SwiftData 永続化
7. PDF 生成
8. SCREEN_DASHBOARD / SCREEN_SETTINGS
```

Phase 2 以降（OBD診断、オークション出品票比較、スタッフ管理の高度化）は `09_ROADMAP.md` を参照。

## 5. 質問が必要なとき

設計書に記載がない仕様判断が必要になった場合、勝手に決めずに以下の形式で確認を求めること：

```
【仕様確認】SCREEN_CAMERA.md には〇〇の記載がありません。
案A: ...（推奨。理由: ...）
案B: ...
```
