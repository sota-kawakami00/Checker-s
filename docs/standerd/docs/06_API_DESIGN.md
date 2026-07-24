# 06_API_DESIGN.md — Service層・外部API設計

| 項目 | 内容 |
|---|---|
| ドキュメントID | DOC-06 |
| バージョン | v1.0 |
| 依存 | 02, 04, 05 |

---

## 1. Service protocol 一覧（クライアント）

各 protocol は `AppraisalKit` / `CameraKit` / `SyncKit` に配置。ViewModel はこれのみ知る。

### 1.1 AuthService

```swift
protocol AuthService: Sendable {
    var currentStaff: Staff? { get }
    func signIn(email: String, password: String) async throws -> Staff
    func signOut() async throws
    func sendPasswordReset(email: String) async throws
    func observeAuthState() -> AsyncStream<Staff?>
}
```

### 1.2 VehicleService

```swift
protocol VehicleService: Sendable {
    func recognizeShaken(from image: UIImage) async throws -> ShakenOCRResult  // FR-201
    func makers() async throws -> [MakerMaster]
    func models(makerCode: String) async throws -> [ModelMaster]
    func grades(makerCode: String, modelCode: String) async throws -> [GradeMaster]
    func equipmentMaster() async throws -> [EquipmentMaster]
}
```

### 1.3 PhotoService

```swift
protocol PhotoService: Sendable {
    func capture(session: CameraSessionHandle) async throws -> CapturedPhoto
    func checkQuality(_ photo: CapturedPhoto, angle: PhotoAngle) async throws -> PhotoQualityResult // 端末内一次判定
    func mask(_ photo: CapturedPhoto) async throws -> MaskedPhoto           // ナンバー/顔（FR-305）
    func persist(_ photo: MaskedPhoto, appraisalId: String, angle: PhotoAngle, damageTag: String?) async throws -> PhotoAsset
}
```

### 1.4 AppraisalService（中核）

```swift
protocol AppraisalService: Sendable {
    func createDraft(vehicle: Vehicle) async throws -> Appraisal
    func updateDraft(_ appraisal: Appraisal) async throws
    func requestAIAppraisal(appraisalId: String) async throws               // キュー投入（UC-02対応）
    func observeAppraisal(id: String) -> AsyncStream<Appraisal>             // Firestoreリスナー⇔SwiftData反映
    func confirm(appraisalId: String, price: Int, adjustmentReason: String?) async throws // FR-407, BR-03
    func setRepairConfirmed(appraisalId: String, state: RepairConfirmedState) async throws // UC-03, BR-04
    func updateCheckItem(appraisalId: String, itemCode: String, checked: Bool) async throws
    func history(filter: HistoryFilter, page: Int) async throws -> [Appraisal] // FR-601, ページング50
    func duplicate(appraisalId: String) async throws -> Appraisal           // FR-602
}
```

### 1.5 PDFService / DashboardService / SyncService

```swift
protocol PDFService: Sendable {
    func generateAppraisalSheet(appraisalId: String) async throws -> URL    // FR-502
}
protocol DashboardService: Sendable {
    func metrics(period: DashboardPeriod) async throws -> DashboardMetrics  // FR-603
    func staffPerformance(period: DashboardPeriod) async throws -> [StaffMetrics]
    func aiDeviationAnalysis(period: DashboardPeriod) async throws -> DeviationReport // FR-604
}
protocol SyncService: Sendable {
    var queueStatus: AsyncStream<SyncQueueStatus> { get }                   // FR-702
    func syncNow() async throws
    func retryFailed() async throws
}
```

## 2. Cloud Functions API 仕様

すべて HTTPS Callable。認証必須（Firebase Auth + App Check）。エラーは `functions.https.HttpsError` の code をクライアントで `AppError` にマップ。

### 2.1 runAppraisal

| 項目 | 内容 |
|---|---|
| 入力 | `{ appraisalId: string, requestId: string, repairConfirmed?: boolean }` |
| 前提 | appraisals ドキュメントと全 photo の Storage アップロード完了 |
| 処理 | 相場取得 → prompts/appraisal_main 構築 → Gemini（responseSchema指定）→ 検証（05 §3.3）→ Firestore 書き込み |
| 出力 | `{ accepted: true }`（結果はFirestoreリスナーで受信） |
| 冪等 | 同一 requestId は再実行せず accepted を返す |
| エラー | `resource-exhausted`(quota) / `failed-precondition`(画像未完) / `internal` |

### 2.2 checkPhotoQuality

| 入力 | `{ photoId, appraisalId, angle }` |
| 処理 | Storage画像 → Gemini（photo_quality schema）→ photoドキュメントの `cloudQuality` 更新 |

### 2.3 fetchMarketPrice

| 入力 | `{ makerCode, modelCode, gradeCode?, modelYear, mileageKm, repairHistory: boolean }` |
| 処理 | 相場プロバイダAPI呼び出し。**プロバイダ差異はここで吸収**し正規化スキーマで返す。24hキャッシュ（Firestore `marketCache`） |
| 出力 | `{ average, median, sampleCount, range: {p25, p75}, trend30d: number, fetchedAt }` |

### 2.4 generateAuctionComparison（Phase 2）

| 入力 | `{ appraisalId, auctionSheetPhotoId }` |
| 出力 | `schemas/auction_comparison.schema.json` 準拠 |

## 3. 相場データAPIの抽象化

- v1は単一プロバイダ想定だが、`MarketPriceProvider` インターフェース（TypeScript）で抽象化し、複数プロバイダの加重平均に将来対応。
- プロバイダ障害時: キャッシュがあれば `stale: true` 付きで返す。キャッシュもない場合、査定は「相場参考なし」モードで続行（confidenceを減点するようプロンプトで指示済み）。

## 4. 認可マトリクス

| 操作 | staff | manager | admin |
|---|---|---|---|
| 査定作成/実行/確定 | ✓ | ✓ | ✓ |
| 信頼度<60%の確定（BR-03例外） | ✗ | ✓ | ✓ |
| 確定済み価格の変更（BR-06） | ✗ | ✓ | ✓ |
| スタッフ招待/無効化 | ✗ | ✓ | ✓ |
| ダッシュボード閲覧 | 自分の実績のみ | 店舗全体 | 店舗全体 |
| 店舗設定変更 | ✗ | ✓ | ✓ |

Security Rules と CF の双方で強制（クライアント判定はUX目的のみ）。
