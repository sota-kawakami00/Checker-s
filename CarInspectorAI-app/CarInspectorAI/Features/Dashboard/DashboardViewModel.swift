import Foundation
import Observation
import Core
import AppraisalKit

/// 店舗ダッシュボード（SCREEN_DASHBOARD.md §4）。
/// 権限による出し分けは View ではなく本 ViewModel の公開プロパティで制御（§15-2）。
@MainActor
@Observable
final class DashboardViewModel {
    enum Phase {
        case loading, content, empty
    }

    var period: DashboardPeriod = .today {
        didSet { Task { await reload() } }
    }

    private(set) var phase: Phase = .loading
    private(set) var metrics: DashboardMetrics?
    private(set) var staffMetrics: [StaffMetrics] = []
    private(set) var deviation: DeviationReport?
    private(set) var metricsError = false
    private(set) var staffError = false
    private(set) var deviationError = false

    /// 認可: ⑤AI乖離カードは manager+（06 §4 / SCR-DASH-01）
    var showsDeviation: Bool {
        (auth.currentStaff?.role ?? .staff) >= .manager
    }

    var isManager: Bool {
        (auth.currentStaff?.role ?? .staff) >= .manager
    }

    private let dashboardService: any DashboardService
    private let auth: any AuthService

    init(dashboardService: any DashboardService, auth: any AuthService) {
        self.dashboardService = dashboardService
        self.auth = auth
    }

    func reload() async {
        // カード単位でエラーを分離（§10: 画面全体を落とさない）
        metricsError = false
        staffError = false
        deviationError = false

        do {
            metrics = try await dashboardService.metrics(period: period)
        } catch {
            metricsError = true
        }
        do {
            staffMetrics = try await dashboardService.staffPerformance(period: period)
        } catch {
            staffError = true
        }
        if showsDeviation {
            do {
                deviation = try await dashboardService.aiDeviationAnalysis(period: period)
            } catch {
                deviationError = true
            }
        }

        if let metrics, metrics.appraisalCount.value == 0 {
            phase = .empty
        } else if metrics == nil && metricsError {
            phase = .empty
        } else {
            phase = .content
        }
    }
}
