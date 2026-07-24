# 03_UI_UX_GUIDELINE.md — UI/UXガイドライン（Liquid Glass デザインシステム）

| 項目 | 内容 |
|---|---|
| ドキュメントID | DOC-03 |
| バージョン | v1.0 |
| 依存 | 00, 各SCREEN_*.md から参照される |

---

## 1. デザイン原則

1. **屋外で使える**: 直射日光下でも読めるコントラスト。重要数値は太く大きく。
2. **片手・手袋**: 主要操作はタップ領域 44pt 以上、画面下部に配置。
3. **ガラスの階層**: Liquid Glass（半透明マテリアル）で情報の階層を表現。ただし可読性が最優先。数値・価格の背面には必ず不透明度の高いレイヤを敷く。
4. **AIの状態を隠さない**: 解析中・信頼度・要確認を常に明示。AIが不確かなときは不確かだと見せる。

## 2. デザイントークン

実装は `DesignSystem` パッケージ。**直値使用禁止**（`CLAUDE.md` §2.3）。

### 2.1 カラー

| トークン | Light | Dark | 用途 |
|---|---|---|---|
| `ci.primary` | #0A84FF | #409CFF | 主要アクション |
| `ci.accent` | #30D158 | #30DB5B | 成功・加点 |
| `ci.warning` | #FF9F0A | #FFB340 | 要確認・注意 |
| `ci.danger` | #FF453A | #FF6961 | 減点・修復歴警告 |
| `ci.priceText` | #1C1C1E | #FFFFFF | 査定価格数値 |
| `ci.bgBase` | systemGroupedBackground | 同 | 画面背景 |
| `ci.glass` | .ultraThinMaterial | 同 | ガラスカード |
| `ci.glassStrong` | .thickMaterial | 同 | 価格など重要情報の背面 |

- 加点は常に `ci.accent`、減点は `ci.danger`。**色だけに依存せず**必ず `+` / `−` 記号を併記（NFR-10）。

### 2.2 タイポグラフィ

| トークン | 定義 | 用途 |
|---|---|---|
| `ci.priceXL` | 40pt bold rounded, monospacedDigit | 査定価格 |
| `ci.titleL` | .title2 bold | 画面見出し |
| `ci.body` | .body | 本文 |
| `ci.caption` | .caption | 補足・根拠説明 |
| `ci.mono` | .body monospacedDigit | 金額・走行距離等の数値 |

- 全て Dynamic Type 対応（`relativeTo:` 指定）。金額は桁ブレ防止のため monospacedDigit 必須。

### 2.3 スペーシング・形状

| トークン | 値 |
|---|---|
| `ci.space.xs / s / m / l / xl` | 4 / 8 / 16 / 24 / 32 |
| `ci.radius.card` | 20 |
| `ci.radius.button` | 14 |
| `ci.shadow.card` | y:2 blur:12 opacity:0.08 |

### 2.4 共通コンポーネント（DesignSystem 提供）

| コンポーネント | 説明 |
|---|---|
| `GlassCard` | ガラスマテリアルの角丸カード。全画面の基本コンテナ |
| `PrimaryButton` / `SecondaryButton` | 主要/副次ボタン。ローディング状態内蔵 |
| `PriceLabel` | 万円区切り・アニメーションカウントアップ付き価格表示 |
| `ConfidenceBadge` | AI信頼度バッジ（>=80: accent, 60-79: warning, <60: danger） |
| `AdjustmentRow` | 加減点1行（アイコン/項目名/±金額/根拠リンク） |
| `StatusChip` | 査定ステータス（下書き/AI査定済/確定/成約/失注） |
| `ShutterButton` | カメラシャッター（72pt） |
| `QualityToast` | 撮影品質判定の結果トースト（✓/✕ + 理由） |
| `EmptyStateView` | 空状態イラスト+CTA |
| `OfflineBanner` | オフライン時の常設バナー |

## 3. モーション・アニメーション

| 場面 | 仕様 |
|---|---|
| 価格表示 | 0→査定額へ0.8sカウントアップ（easeOut）。`accessibilityReduceMotion` 時は即時表示 |
| 品質判定トースト | 下から spring(response:0.35, damping:0.8)。OK=1.2s後自動消滅、NG=手動クローズ |
| AI解析中 | 段階メッセージ（§SCREEN_APPRAISAL系参照）+ 不確定プログレス。30秒超で文言切替（NFR-02） |
| 画面遷移 | 標準 NavigationStack 遷移。モーダルは `.presentationDetents([.medium, .large])` |
| 修復歴警告 | カード出現時に1回だけ軽い haptic (.warning) |

## 4. 状態表現の統一ルール

全画面で以下の5状態を必ず設計・実装する（SCREEN_*.md に個別定義）：

1. `loading`（スケルトン表示。スピナー単体は禁止）
2. `content`（正常）
3. `empty`（空状態: イラスト+説明+CTA）
4. `error`（AppError別の文言+回復アクション）
5. `offline`（OfflineBanner + 可能な操作は継続）

## 5. アクセシビリティ

- VoiceOver: 価格は「査定価格 百八十三万円」と読み上げ（数値の分解読み禁止）。加減点は「加点 人気カラー 五万円」形式。
- Dynamic Type: xxxLarge まで崩れないこと。価格カードは折返しではなく段組み変更で対応。
- コントラスト: ガラス上のテキストは背面に `ci.glassStrong` を敷き 4.5:1 以上を確保。
- 触覚: 品質判定OK=.success、NG=.error、修復歴警告=.warning。

## 6. 文言トーン

- 敬体・簡潔。「〜してください」まで書く（例:「ボンネットが切れています。少し下がって撮影してください」）。
- AI出力は断定を避ける:「修復歴の可能性があります（78%）。現車をご確認ください」。
- エラーは責めない・技術用語を出さない（`CLAUDE.md` §2.4）。
