import Foundation
import Observation
import Core
import AppraisalKit

/// ホーム画面（SCREEN_HOME.md §4）
@MainActor
@Observable
final class HomeViewModel {
    enum Phase {
        case loading, content, empty
    }

    private(set) var phase: Phase = .loading
    private(set) var inProgress: [Appraisal] = []      // 下書き/AI解析中/要確認
    private(set) var recentConfirmed: [Appraisal] = []
    private(set) var todayCount = 0                    // ローカル集計（ダッシュボードの厳密値とは別物）
    private(set) var queueStatus = SyncQueueStatus()
    private(set) var staffName = ""
    private(set) var storeName = ""

    private let appraisalService: any AppraisalService
    private let syncService: any SyncService
    private let auth: any AuthService
    @ObservationIgnored private nonisolated(unsafe) var statusTask: Task<Void, Never>?

    init(appraisalService: any AppraisalService, syncService: any SyncService, auth: any AuthService, storeName: String) {
        self.appraisalService = appraisalService
        self.syncService = syncService
        self.auth = auth
        self.storeName = storeName
    }

    func onAppear() async {
        staffName = auth.currentStaff?.displayName ?? ""
        await reload()
        // キュー状態の購読 → OfflineBanner（SCREEN_HOME §2-⑥）
        if statusTask == nil {
            queueStatus = syncService.currentQueueStatus
            let stream = syncService.queueStatus
            statusTask = Task { [weak self] in
                for await status in stream {
                    self?.queueStatus = status
                }
            }
        }
    }

    deinit {
        statusTask?.cancel()
    }

    func reload() async {
        do {
            let all = try await appraisalService.history(filter: .all, page: 0)
            inProgress = all.filter { appraisal in
                switch appraisal.status {
                case .draft, .aiRunning:
                    return true
                case .aiCompleted:
                    return true   // 要確認（修復歴・低confidence含む）
                default:
                    return false
                }
            }
            recentConfirmed = all
                .filter { $0.status == .confirmed || $0.status == .won }
                .prefix(3)
                .map { $0 }
            let calendar = Calendar.current
            todayCount = all.filter { calendar.isDateInToday($0.createdAt) }.count
            phase = all.isEmpty ? .empty : .content
        } catch {
            // ホーム機能は停止させない（SCREEN_HOME §10: キャッシュ表示+トーストのみ）
            phase = inProgress.isEmpty && recentConfirmed.isEmpty ? .empty : .content
        }
    }

    /// 進行中カードの補助ラベル（修復歴・低confidenceの要確認判定）
    func needsAttention(_ appraisal: Appraisal) -> Bool {
        guard appraisal.status == .aiCompleted else { return false }
        let lowConfidence = (appraisal.aiConfidence ?? 1) < 0.8
        let repairSuspected = (appraisal.repairProbability ?? 0) >= ConfirmGuard.repairSuspectThreshold
        return lowConfidence || repairSuspected
    }

    func vehicleLabel(_ appraisal: Appraisal) -> String {
        (appraisalService as? AppraisalServiceImpl)?.vehicleLabel(appraisal.vehicle)
            ?? "\(appraisal.vehicle.makerCode) \(appraisal.vehicle.modelCode)"
    }
}
