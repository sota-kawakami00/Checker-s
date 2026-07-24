import Foundation
import Observation
import Core
import AppraisalKit

/// 査定履歴（SCREEN_HISTORY.md §4）
@MainActor
@Observable
final class HistoryViewModel {
    enum Phase {
        case loading, content, empty
    }

    private(set) var phase: Phase = .loading
    private(set) var items: [Appraisal] = []
    private(set) var hasMore = true
    var error: AppError?

    // フィルタ状態（②）
    var searchText = "" {
        didSet { scheduleSearch() }
    }
    var statusFilter: AppraisalStatus? {
        didSet { Task { await reload() } }
    }
    var repairSuspectedOnly = false {
        didSet { Task { await reload() } }
    }
    var periodDays: Int? {
        didSet { Task { await reload() } }
    }
    var mineOnly = false {
        didSet { Task { await reload() } }
    }

    private var page = 0
    private var searchDebounce: Task<Void, Never>?
    private let appraisalService: any AppraisalService
    private let auth: any AuthService

    init(appraisalService: any AppraisalService, auth: any AuthService) {
        self.appraisalService = appraisalService
        self.auth = auth
    }

    private var filter: HistoryFilter {
        HistoryFilter(
            searchText: searchText,
            from: periodDays.map { Date.now.addingTimeInterval(-Double($0) * 86_400) },
            to: nil,
            statuses: statusFilter.map { [$0] } ?? [],
            staffId: mineOnly ? auth.currentStaff?.id : nil,
            repairSuspectedOnly: repairSuspectedOnly
        )
    }

    /// デバウンス検索 300ms（§4）
    private func scheduleSearch() {
        searchDebounce?.cancel()
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func reload() async {
        page = 0
        do {
            let first = try await appraisalService.history(filter: filter, page: 0)
            items = first
            hasMore = first.count == HistoryFilterEngine.pageSize
            phase = first.isEmpty ? .empty : .content
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
            phase = items.isEmpty ? .empty : .content
        }
    }

    /// ページング: 末尾到達で次50件（NFR-03）
    func loadMore() async {
        guard hasMore else { return }
        page += 1
        do {
            let next = try await appraisalService.history(filter: filter, page: page)
            items.append(contentsOf: next)
            hasMore = next.count == HistoryFilterEngine.pageSize
        } catch {
            hasMore = false
        }
    }

    // 行スワイプ操作（④）
    func duplicate(id: String) async -> String? {
        do {
            let draft = try await appraisalService.duplicate(appraisalId: id)
            return draft.id
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
            return nil
        }
    }

    func markWon(id: String) async {
        await setOutcome(id: id, won: true)
    }

    func markLost(id: String) async {
        await setOutcome(id: id, won: false)
    }

    private func setOutcome(id: String, won: Bool) async {
        do {
            try await appraisalService.setOutcome(appraisalId: id, won: won)
            await reload()
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
        }
    }

    func vehicleLabel(_ appraisal: Appraisal) -> String {
        (appraisalService as? AppraisalServiceImpl)?.vehicleLabel(appraisal.vehicle)
            ?? "\(appraisal.vehicle.makerCode) \(appraisal.vehicle.modelCode)"
    }

    /// 期限切れ間近 warning ドット（BR-05 / SCR-HIS-04）
    func isExpiringSoon(_ appraisal: Appraisal) -> Bool {
        HistoryFilterEngine.isExpiringSoon(appraisal)
    }
}
