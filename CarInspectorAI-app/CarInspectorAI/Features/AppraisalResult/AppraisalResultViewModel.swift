import Foundation
import Observation
import Core
import AppraisalKit

enum ResultPhase: Equatable {
    case running, failed, reviewing, confirmed
}

/// 査定結果画面（SCREEN_APPRAISAL_RESULT.md §4）。Running も同一画面の phase 分岐（§15-2）。
@MainActor
@Observable
final class AppraisalResultViewModel {

    private(set) var appraisal: Appraisal?
    private(set) var result: AppraisalResult?
    private(set) var phase: ResultPhase = .running
    private(set) var progressMessageIndex = 0
    private(set) var isOverThirtySeconds = false     // NFR-02: 30秒超で文言切替
    var isAdjustSheetPresented = false
    var adjustedPrice: Int?
    var adjustmentReason = ""
    var error: AppError?
    private(set) var pdfURL: URL?
    private(set) var isGeneratingPDF = false
    /// manager承認が必要な状態（BR-03: staff 不可 → 承認シートへ）
    var isManagerApprovalPresented = false

    private let appraisalService: any AppraisalService
    private let pdfService: any PDFService
    private let auth: any AuthService
    private let masters: MasterCatalog
    @ObservationIgnored private nonisolated(unsafe) var observeTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var progressTask: Task<Void, Never>?
    private var runningSince: Date?

    init(
        appraisalService: any AppraisalService,
        pdfService: any PDFService,
        auth: any AuthService,
        masters: MasterCatalog
    ) {
        self.appraisalService = appraisalService
        self.pdfService = pdfService
        self.auth = auth
        self.masters = masters
    }

    deinit {
        observeTask?.cancel()
        progressTask?.cancel()
    }

    // MARK: - 購読（§5: リスナー⇔SwiftData反映のストリーム。CFを直接ポーリングしない）

    func observe(appraisalId: String) async {
        guard observeTask == nil else { return }
        let stream = appraisalService.observeAppraisal(id: appraisalId)
        observeTask = Task { [weak self] in
            for await appraisal in stream {
                self?.apply(appraisal)
            }
        }
        startProgressMessages()
    }

    private func apply(_ appraisal: Appraisal) {
        self.appraisal = appraisal
        switch appraisal.status {
        case .aiRunning:
            phase = appraisal.aiFailureReason == nil ? .running : .failed
            if phase == .running, runningSince == nil {
                runningSince = .now
            }
        case .aiCompleted:
            decodeResult(appraisal)
            phase = .reviewing
            runningSince = nil
        case .confirmed, .won, .lost, .expired:
            decodeResult(appraisal)
            phase = .confirmed
        case .draft:
            phase = .reviewing
        }
    }

    private func decodeResult(_ appraisal: Appraisal) {
        guard let data = appraisal.aiResultJSON else {
            result = nil
            return
        }
        do {
            // デコード失敗は aiInvalidResponse として再試行導線（§5）
            result = try AppraisalResult.decode(from: data)
        } catch {
            result = nil
            self.error = .aiInvalidResponse(reason: "decode")
            phase = .failed
        }
    }

    /// Running: 段階メッセージ（3秒毎切替、30秒超で待機文言 NFR-02）
    private func startProgressMessages() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.phase == .running else { continue }
                self.progressMessageIndex = (self.progressMessageIndex + 1) % 3
                if let since = self.runningSince, Date.now.timeIntervalSince(since) > 30 {
                    self.isOverThirtySeconds = true
                }
            }
        }
    }

    // MARK: - 操作

    func retryAI() async {
        guard let appraisal else { return }
        do {
            try await appraisalService.requestAIAppraisal(appraisalId: appraisal.id)
            runningSince = .now
            isOverThirtySeconds = false
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
        }
    }

    func setRepairConfirmed(_ state: RepairConfirmedState) async {
        guard let appraisal else { return }
        do {
            // 「あり」→ BR-04 再査定発火（running へ戻る）
            try await appraisalService.setRepairConfirmed(appraisalId: appraisal.id, state: state)
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
        }
    }

    func toggleCheckItem(_ code: String) async {
        guard let appraisal else { return }
        let isCurrentlyUnchecked = appraisal.uncheckedItems.contains(code)
        do {
            try await appraisalService.updateCheckItem(appraisalId: appraisal.id, itemCode: code, checked: isCurrentlyUnchecked)
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
        }
    }

    // MARK: - 確定ガード（§15-5: canConfirm 1箇所に集約）

    var effectivePrice: Int {
        adjustedPrice ?? appraisal?.aiProposedPrice ?? 0
    }

    var confirmBlockers: [ConfirmBlocker] {
        guard let appraisal else { return [.aiNotCompleted] }
        return ConfirmGuard.blockers(
            status: appraisal.status,
            aiConfidence: appraisal.aiConfidence,
            repairProbability: appraisal.repairProbability,
            repairConfirmedState: appraisal.repairConfirmedState,
            aiProposedPrice: appraisal.aiProposedPrice,
            requestedPrice: effectivePrice,
            adjustmentReason: adjustmentReason,
            role: auth.currentStaff?.role ?? .staff
        )
    }

    var canConfirm: Bool {
        phase == .reviewing && confirmBlockers.isEmpty
    }

    /// 確定不可の理由（accessibilityHint / UI表示。SCR-RES-04）
    var confirmBlockReasonKey: String? {
        guard phase == .reviewing else { return nil }
        guard let first = confirmBlockers.first else { return nil }
        switch first {
        case .repairUnconfirmed: return "result.block.repairUnconfirmed"
        case .lowConfidenceNeedsManager: return "result.block.lowConfidence"
        case .adjustmentReasonRequired: return "result.block.reasonRequired"
        case .priceUnitInvalid: return "result.block.priceUnit"
        case .aiNotCompleted: return "result.block.notCompleted"
        }
    }

    func confirm() async {
        guard let appraisal else { return }
        // BR-03: 低confidence + staff は manager 承認シートへ（SCR-RES-03）
        if confirmBlockers.contains(.lowConfidenceNeedsManager) {
            isManagerApprovalPresented = true
            return
        }
        do {
            try await appraisalService.confirm(
                appraisalId: appraisal.id,
                price: effectivePrice,
                adjustmentReason: adjustmentReason.isEmpty ? nil : adjustmentReason
            )
            isAdjustSheetPresented = false
        } catch let appError as AppError {
            if case .forbidden = appError {
                isManagerApprovalPresented = true
            } else {
                error = appError
            }
        } catch {
            self.error = .serverError(code: 0)
        }
    }

    /// 調整シート: 1万円単位ステッパー（BR-01）
    func adjustPrice(by delta: Int) {
        let base = effectivePrice
        adjustedPrice = max(0, base + delta)
    }

    var priceDiffFromAI: Int {
        guard let proposed = appraisal?.aiProposedPrice else { return 0 }
        return effectivePrice - proposed
    }

    /// 調整保存可否（SCR-RES-06: 理由空は保存不可）
    var canSaveAdjustment: Bool {
        guard adjustedPrice != nil else { return false }
        if priceDiffFromAI != 0 {
            return !adjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    // MARK: - PDF（FR-502/503）

    func generatePDF() async -> URL? {
        guard let appraisal else { return nil }
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        do {
            let url = try await pdfService.generateAppraisalSheet(appraisalId: appraisal.id)
            pdfURL = url
            return url
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
            return nil
        }
    }

    // MARK: - 表示ヘルパ

    var vehicleLabel: String {
        guard let vehicle = appraisal?.vehicle else { return "" }
        return "\(masters.makerName(vehicle.makerCode)) \(masters.modelName(vehicle.modelCode))"
    }

    func checkItemLabel(_ code: String) -> String {
        masters.checkItem(code)?.label ?? code
    }

    func checkItemHint(_ code: String) -> String {
        masters.checkItem(code)?.hint ?? ""
    }

    var allCheckItemCodes: [String] {
        masters.checkItems.map(\.code)
    }

    /// 市場乖離率（§2-③）
    var marketDeviationRate: Double? {
        guard let result, result.marketAveragePrice > 0 else { return nil }
        return Double(result.appraisedPrice - result.marketAveragePrice) / Double(result.marketAveragePrice)
    }

    func photoPath(for photoId: String) -> String? {
        appraisal?.photos.first { $0.id == photoId }
            .flatMap { $0.localMaskedPath ?? $0.localOriginalPath }
    }

    var repairSuspected: Bool {
        (appraisal?.repairProbability ?? 0) >= ConfirmGuard.repairSuspectThreshold
    }
}
