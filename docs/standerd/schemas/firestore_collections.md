# firestore_collections.md — Firestore コレクション完全定義

`04_DATA_MODEL.md` §3 の正式版。フィールド型は Firestore 型（string/number/boolean/timestamp/map/array）。

---

## stores/{storeId}

| field | type | 備考 |
|---|---|---|
| name | string | |
| address | string | |
| logoStoragePath | string? | 査定書ロゴ |
| settings | map | { targetMarginRate: number?, forceAppLock: boolean, promptVariant: string? } |
| createdAt / updatedAt | timestamp | |

## stores/{storeId}/staffs/{staffId}

| field | type | 備考 |
|---|---|---|
| displayName | string | |
| email | string | |
| role | string | "staff" \| "manager" \| "admin"（正はAuthカスタムクレーム。本フィールドは表示用ミラー） |
| active | boolean | 無効化フラグ（FR-104） |
| createdAt | timestamp | |

## stores/{storeId}/appraisals/{appraisalId}

| field | type | 備考 |
|---|---|---|
| staffId | string | 作成者 |
| status | string | draft/aiRunning/aiCompleted/confirmed/won/lost/expired |
| vehicle | map | AppraisalRequest.vehicle と同形（vinはマスク済のみ保存） |
| photos | array<map> | { photoId, angle, damageTag?, storagePath, qualityPassed, cloudQuality? } メタのみ。画像本体はStorage |
| aiStatus | map? | { state: "running"\|"done"\|"failed", reason?, requestId, promptVersion, startedAt, finishedAt } |
| aiResult | map? | appraisal_result.schema.json 準拠（CF検証済のみ書込） |
| aiProposedPrice | number? | aiResult.appraisedPrice のミラー（クエリ用） |
| confirmedPrice | number? | |
| adjustmentReason | string? | |
| repairConfirmedState | string? | none/confirmedYes/confirmedNo/unknown |
| checkedItems | array<string> | スタッフ手動チェック済み項目コード |
| marketAveragePrice | number? | |
| expiresAt | timestamp? | 確定+7日（BR-05） |
| deletedAt | timestamp? | 論理削除 |
| createdAt / updatedAt | timestamp | |

### stores/{storeId}/appraisals/{id}/adjustmentLogs/{logId}（BR-06）

| field | type |
|---|---|
| beforePrice / afterPrice | number |
| reason | string |
| staffId | string |
| at | timestamp |

### stores/{storeId}/appraisals/{id}/auditLogs/{logId}

| field | type | 備考 |
|---|---|---|
| kind | string | pdfGenerated/exported/... |
| staffId | string | |
| at | timestamp | |

## marketCache/{cacheKey}

| field | type | 備考 |
|---|---|---|
| key | string | maker_model_grade_year_mileageBand_repair |
| payload | map | fetchMarketPrice 正規化結果 |
| fetchedAt | timestamp | TTL 24h（CF判定） |

## masters/（読み取り専用・CF/コンソールのみ書込）

```
masters/vehicles/{makerCode}                 { name, sort }
masters/vehicles/{makerCode}/models/{code}   { name, years: [..], grades: [{code, name, type}] }
masters/equipments/{code}                    { label, sort }
masters/checkItems/{code}                    { label, weight, hint, sort }
masters/colors/{code}                        { label, popular: boolean }
```

## Storage パス規約

```
stores/{storeId}/appraisals/{appraisalId}/photos/{photoId}.jpg   # マスク済のみ
stores/{storeId}/assets/logo.png
```

## 変更ルール

- 破壊的変更（型変更・required追加・enum削除）は 09_ROADMAP の変更履歴に記録し、CF・アプリの後方互換期間を設ける。
