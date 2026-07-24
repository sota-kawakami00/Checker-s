# 07_SECURITY.md — セキュリティ・プライバシー設計

| 項目 | 内容 |
|---|---|
| ドキュメントID | DOC-07 |
| バージョン | v1.0 |
| 依存 | 02, 04, 06 |

---

## 1. 脅威モデル（要約）

| 脅威 | 対策 |
|---|---|
| 他店舗データへの越境アクセス | Firestore Rules でテナント境界強制（§3）+ CF側二重チェック |
| APIキー抽出（Gemini/相場） | 端末にキーを置かない。CFゲートウェイのみが保持（02 §8） |
| 不正クライアントからのCF呼び出し | Firebase App Check（DeviceCheck/App Attest）必須 |
| 通信盗聴 | TLS1.3。ATS例外なし |
| 端末紛失 | 端末内データはiOS Data Protection（`.completeUntilFirstUserAuthentication`）。アプリロック（Face ID）オプション |
| 個人情報のAIベンダー送出 | §2 のマスキング・除去を送信前に必須実施 |
| 退職スタッフのアクセス残存 | manager による無効化（FR-104）→ Auth disable + カスタムクレーム失効 |

## 2. 個人情報・プライバシー

### 2.1 AIへ送信してよいもの / ダメなもの

| データ | Gemini送信 | 備考 |
|---|---|---|
| 車両画像（マスキング済） | ✓ | ナンバー・人物顔をマスキング後のみ |
| 車両画像（原本） | ✗ | 端末外に出さない |
| 車台番号(VIN) | △下6桁マスク | 個体識別性が高いため下6桁を `******` 化して送信 |
| 顧客氏名・連絡先 | ✗ | そもそもv1では収集しない |
| GPS/EXIF | ✗ | アップロード前に全EXIF除去（FR-306と同処理） |
| スタッフID | ✗ | AIには不要。監査ログはCF側で別途保持 |

### 2.2 マスキングパイプライン（CameraKit）

```
撮影原本 → Vision: ナンバープレート矩形検出 + 顔検出
        → CoreImageでぼかし（ガウシアン r=20相当）
        → EXIF/GPS除去 → リサイズ・圧縮 → localMaskedPath 保存
        → これのみアップロード可（PhotoService.persistが強制）
```

- 検出失敗のフォールバック: 撮影レビュー画面で手動マスキング（指でなぞる）を提供。マスク未確認の写真はアップロード不可にはしない（業務停止回避）が、`maskVerified: false` を記録。

## 3. Firestore Security Rules（方針＋抜粋）

```
match /stores/{storeId}/{document=**} {
  allow read, write: if request.auth != null
    && request.auth.token.storeId == storeId;
}

match /stores/{storeId}/appraisals/{id} {
  // 確定済み価格の変更は manager 以上（BR-06）
  allow update: if request.auth.token.storeId == storeId
    && (resource.data.status != 'confirmed'
        || request.auth.token.role in ['manager','admin']
        || !request.resource.data.diff(resource.data).affectedKeys().hasAny(['confirmedPrice']));
}

match /masters/{document=**} {
  allow read: if request.auth != null;
  allow write: if false;   // 管理コンソール/CFのみ
}
```

- `storeId` / `role` は Auth カスタムクレームで付与（招待受諾時にCFが設定）。
- Storage Rules も同構造（`stores/{storeId}/appraisals/{id}/photos/…`）。

## 4. 認証

- v1: メール+パスワード（最低10文字、漏洩パスワードチェック有効化）
- セッション: Firebase標準。アプリ側で30日無操作は再ログイン要求
- アプリロック: Face ID / Touch ID（設定でON。manager が店舗強制ONも可）

## 5. 監査ログ

| イベント | 記録場所 | 内容 |
|---|---|---|
| 価格確定・変更 | `adjustmentLogs`（BR-06） | before/after/reason/staffId/at |
| AI呼び出し | CF構造化ログ（BigQueryエクスポート） | requestId, storeId, promptVersion, tokens, latency, 検証結果 |
| 認証イベント | Firebase Auth ログ | 標準 |
| データエクスポート/PDF生成 | appraisal サブコレクション | staffId, at, 出力形式 |

## 6. 秘密情報管理

- クライアント: APIキーなし。Firebase設定は GoogleService-Info.plist（公開情報扱いだが gitignore し CI で注入）
- CF: Secret Manager（`GEMINI_API_KEY`, `MARKET_API_KEY`）。環境（dev/stg/prod）別プロジェクト分離
- `.xcconfig` / `.env` 系は全て gitignore（AGENTS.md）

## 7. コンプライアンスメモ

- 個人情報保護法: 車両画像に写り込む第三者の顔はマスキング（§2.2）で対応
- 古物営業法まわりの本人確認情報は v1 スコープ外（Phase 3で契約機能と同時検討）
- データ保管: 東京リージョン（asia-northeast1）固定
