import Foundation
import SwiftData
import Core

/// AppraisalService の実装（06 §1.4）。
/// 全書き込みはまず SwiftData（Offline First, 02 §5.1）。同期は SyncEnqueuing 経由でキュー投入。
@MainActor
public final class AppraisalServiceImpl: AppraisalService {

    /// 査定の有効期限（BR-05: 確定から7日間）
    public static let expiryInterval: TimeInterval = 7 * 24 * 3600

    /// 通知購読クロージャ生存中の SwiftData スタック解放を防ぐため container を強参照する
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let auth: AuthService
    private let sync: SyncEnqueuing
    private let masters: MasterCatalog
    private let notifier: AppraisalChangeNotifier
    private let now: @Sendable () -> Date
    private let logger = CILogger.logger(category: "AppraisalService")

    public init(
        container: ModelContainer,
        auth: AuthService,
        sync: SyncEnqueuing,
        masters: MasterCatalog,
        notifier: AppraisalChangeNotifier = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.modelContainer = container
        self.context = container.mainContext
        self.auth = auth
        self.sync = sync
        self.masters = masters
        self.notifier = notifier
        self.now = now
    }

    // MARK: - 参照

    public func appraisal(id: String) async throws -> Appraisal {
        guard let found = try fetchAppraisal(id) else {
            throw AppError.notFound(entity: "Appraisal")
        }
        refreshExpiry(found)
        return found
    }

    private func fetchAppraisal(_ id: String) throws -> Appraisal? {
        var descriptor = FetchDescriptor<Appraisal>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private var currentStaff: Staff {
        get throws {
            guard let staff = auth.currentStaff else { throw AppError.unauthenticated }
            return staff
        }
    }

    // MARK: - 下書き（FR-205）

    public func createDraft(vehicle: Vehicle) async throws -> Appraisal {
        let staff = try currentStaff
        let appraisal = Appraisal(storeId: staff.storeId, staffId: staff.id, status: .draft, vehicle: vehicle)
        context.insert(appraisal)
        try save()
        return appraisal
    }

    public func updateDraft(_ appraisal: Appraisal) async throws {
        appraisal.updatedAt = now()
        try save()
        notifier.post(appraisalId: appraisal.id)
    }

    // MARK: - AI査定（FR-401〜408 / UC-02）

    public func requestAIAppraisal(appraisalId: String) async throws {
        let appraisal = try await self.appraisal(id: appraisalId)
        guard !appraisal.photos.isEmpty else {
            throw AppError.validation(reason: "photosRequired")
        }
        appraisal.status = .aiRunning
        appraisal.aiFailureReason = nil
        appraisal.syncState = .pendingUpload
        appraisal.updatedAt = now()
        try save()

        // SyncKit が (1)ドキュメント (2)マスク済画像 (3)CF runAppraisal を順に実行（SCREEN_CAMERA §6 / 05 §1）
        sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        for photo in appraisal.photos where photo.uploadState != .done {
            sync.enqueue(kind: .uploadPhoto, targetId: photo.id, appraisalId: appraisal.id)
        }
        sync.enqueue(kind: .requestAIAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        notifier.post(appraisalId: appraisal.id)
        sync.kick()
    }

    public func observeAppraisal(id: String) -> AsyncStream<Appraisal> {
        AsyncStream { continuation in
            if let current = try? fetchAppraisal(id) {
                Self.yieldOnMain(current, to: continuation)
            }
            let token = notifier.subscribe(appraisalId: id) { [weak self] appraisalId in
                guard let self, let updated = try? self.fetchAppraisal(appraisalId) else { return }
                Self.yieldOnMain(updated, to: continuation)
            }
            let notifier = self.notifier
            continuation.onTermination = { _ in
                Task { @MainActor in
                    notifier.unsubscribe(token)
                }
            }
        }
    }

    /// @Model は Sendable でないため yield が region チェックに掛かるが、
    /// 本ストリームの生産・消費はともに MainActor（ViewModel）に閉じているため安全。
    private static func yieldOnMain(_ appraisal: Appraisal, to continuation: AsyncStream<Appraisal>.Continuation) {
        nonisolated(unsafe) let value = appraisal
        continuation.yield(value)
    }

    // MARK: - 確定（FR-407 / BR-01/03/06 / UC-03）

    public func confirm(appraisalId: String, price: Int, adjustmentReason: String?) async throws {
        let staff = try currentStaff
        let appraisal = try await self.appraisal(id: appraisalId)

        // BR-06: 確定済み価格の変更は manager 以上
        if appraisal.status == .confirmed, staff.role < .manager {
            throw AppError.forbidden
        }

        let blockers = ConfirmGuard.blockers(
            status: appraisal.status == .confirmed ? .aiCompleted : appraisal.status,
            aiConfidence: appraisal.aiConfidence,
            repairProbability: appraisal.repairProbability,
            repairConfirmedState: appraisal.repairConfirmedState,
            aiProposedPrice: appraisal.aiProposedPrice,
            requestedPrice: price,
            adjustmentReason: adjustmentReason,
            role: staff.role
        )
        if blockers.contains(.lowConfidenceNeedsManager) {
            throw AppError.forbidden
        }
        if blockers.contains(.repairUnconfirmed) {
            throw AppError.validation(reason: "repairUnconfirmed")
        }
        if blockers.contains(.adjustmentReasonRequired) {
            throw AppError.validation(reason: "adjustmentReasonRequired")
        }
        if blockers.contains(.priceUnitInvalid) {
            throw AppError.validation(reason: "priceUnitInvalid")
        }
        if blockers.contains(.aiNotCompleted) {
            throw AppError.validation(reason: "aiNotCompleted")
        }

        // BR-06: 変更履歴を全件保存
        let log = AdjustmentLog(
            appraisalId: appraisal.id,
            beforePrice: appraisal.confirmedPrice ?? appraisal.aiProposedPrice,
            afterPrice: price,
            reason: adjustmentReason,
            staffId: staff.id,
            at: now()
        )
        context.insert(log)

        appraisal.confirmedPrice = price
        appraisal.adjustmentReason = adjustmentReason
        appraisal.status = .confirmed
        appraisal.expiresAt = now().addingTimeInterval(Self.expiryInterval)   // BR-05
        appraisal.syncState = .pendingUpload
        appraisal.updatedAt = now()
        try save()

        sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        notifier.post(appraisalId: appraisal.id)
        sync.kick()
    }

    // MARK: - 修復歴確認（UC-03 / BR-04）

    public func setRepairConfirmed(appraisalId: String, state: RepairConfirmedState) async throws {
        let appraisal = try await self.appraisal(id: appraisalId)
        appraisal.repairConfirmedState = state
        appraisal.syncState = .pendingUpload
        appraisal.updatedAt = now()

        if state == .confirmedYes {
            // BR-04: 修復歴「あり」確定時は修復歴ありの相場テーブルで再計算（再査定を発行）
            appraisal.status = .aiRunning
            appraisal.aiFailureReason = nil
            try save()
            sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
            sync.enqueue(kind: .requestAIAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        } else {
            try save()
            sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        }
        notifier.post(appraisalId: appraisal.id)
        sync.kick()
    }

    // MARK: - 査定漏れ診断（FR-406）

    public func updateCheckItem(appraisalId: String, itemCode: String, checked: Bool) async throws {
        let appraisal = try await self.appraisal(id: appraisalId)
        if checked {
            appraisal.uncheckedItems.removeAll { $0 == itemCode }
            if !appraisal.checkedItems.contains(itemCode) {
                appraisal.checkedItems.append(itemCode)
            }
        } else {
            appraisal.checkedItems.removeAll { $0 == itemCode }
            if !appraisal.uncheckedItems.contains(itemCode) {
                appraisal.uncheckedItems.append(itemCode)
            }
        }
        // スコア即時再計算（SCREEN_APPRAISAL_RESULT §2-⑤、ローカル）
        let allCodes = Set(masters.checkItems.map(\.code))
        let checkedCodes = allCodes.subtracting(appraisal.uncheckedItems)
        appraisal.completenessScore = masters.completenessScore(checkedCodes: checkedCodes)
        appraisal.syncState = .pendingUpload
        appraisal.updatedAt = now()
        try save()
        sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        notifier.post(appraisalId: appraisal.id)
        sync.kick()
    }

    // MARK: - 履歴（FR-601/602）

    public func history(filter: HistoryFilter, page: Int) async throws -> [Appraisal] {
        let descriptor = FetchDescriptor<Appraisal>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = try context.fetch(descriptor)
        all.forEach(refreshExpiry)
        let filtered = all.filter { appraisal in
            HistoryFilterEngine.matches(appraisal, filter: filter, vehicleLabel: vehicleLabel(appraisal.vehicle))
        }
        return HistoryFilterEngine.page(filtered, page: page)
    }

    public func duplicate(appraisalId: String) async throws -> Appraisal {
        let source = try await self.appraisal(id: appraisalId)
        let staff = try currentStaff
        let vehicle = source.vehicle
        // 車両情報のみ引継ぎ。写真・AI結果は複製しない（SCR-HIS-02）
        let copied = Vehicle(
            vin: vehicle.vin,
            makerCode: vehicle.makerCode,
            modelCode: vehicle.modelCode,
            gradeCode: vehicle.gradeCode,
            modelYear: vehicle.modelYear,
            firstRegistrationYM: vehicle.firstRegistrationYM,
            mileageKm: vehicle.mileageKm,
            colorCode: vehicle.colorCode,
            inspectionExpiry: vehicle.inspectionExpiry,
            equipments: vehicle.equipments
        )
        let draft = Appraisal(storeId: staff.storeId, staffId: staff.id, status: .draft, vehicle: copied)
        context.insert(draft)
        try save()
        return draft
    }

    public func setOutcome(appraisalId: String, won: Bool) async throws {
        let appraisal = try await self.appraisal(id: appraisalId)
        guard appraisal.status == .confirmed else {
            throw AppError.validation(reason: "outcomeRequiresConfirmed")
        }
        appraisal.status = won ? .won : .lost
        appraisal.syncState = .pendingUpload
        appraisal.updatedAt = now()
        try save()
        sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        notifier.post(appraisalId: appraisal.id)
        sync.kick()
    }

    // MARK: - 内部

    /// BR-05: 有効期限切れの検出（確定から7日）
    private func refreshExpiry(_ appraisal: Appraisal) {
        if appraisal.status == .confirmed, let expiresAt = appraisal.expiresAt, expiresAt < now() {
            appraisal.status = .expired
            appraisal.syncState = .pendingUpload
            try? save()
            sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        }
    }

    public func vehicleLabel(_ vehicle: Vehicle) -> String {
        "\(masters.makerName(vehicle.makerCode)) \(masters.modelName(vehicle.modelCode))"
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            logger.error("SwiftData save failed: \(error.localizedDescription)")
            throw AppError.storageFull
        }
    }
}
