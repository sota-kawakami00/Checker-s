import Foundation
import SwiftData
import Core

/// DashboardService 実装（06 §1.5 / SCREEN_DASHBOARD.md §5）。
/// 集計はローカル SwiftData 集計（確定値は Firestore 同期後に一致）。
@MainActor
public final class DashboardServiceImpl: DashboardService {
    private let context: ModelContext
    private let auth: AuthService
    private let masters: MasterCatalog
    private let now: @Sendable () -> Date

    public init(context: ModelContext, auth: AuthService, masters: MasterCatalog, now: @escaping @Sendable () -> Date = { .now }) {
        self.context = context
        self.auth = auth
        self.masters = masters
        self.now = now
    }

    public func metrics(period: DashboardPeriod) async throws -> DashboardMetrics {
        let ranges = DashboardCalculator.dateRanges(period: period, now: now())
        let current = try snapshots(in: ranges.current)
        let previous = try snapshots(in: ranges.previous)
        return DashboardCalculator.metrics(current: current, previous: previous)
    }

    public func staffPerformance(period: DashboardPeriod) async throws -> [StaffMetrics] {
        guard let staff = auth.currentStaff else { throw AppError.unauthenticated }
        let ranges = DashboardCalculator.dateRanges(period: period, now: now())
        var performance = DashboardCalculator.staffPerformance(try snapshots(in: ranges.current))
        // 認可マトリクス（06 §4）: staff は自分の実績のみ
        if staff.role == .staff {
            performance = performance.filter { $0.staffId == staff.id }
        }
        return performance
    }

    public func aiDeviationAnalysis(period: DashboardPeriod) async throws -> DeviationReport {
        guard let staff = auth.currentStaff else { throw AppError.unauthenticated }
        // FR-604: manager 以上のみ
        guard staff.role >= .manager else { throw AppError.forbidden }
        let ranges = DashboardCalculator.dateRanges(period: period, now: now())
        return DashboardCalculator.deviationReport(try snapshots(in: ranges.current))
    }

    private func snapshots(in range: Range<Date>) throws -> [DashboardCalculator.Snapshot] {
        let descriptor = FetchDescriptor<Appraisal>(sortBy: [SortDescriptor(\.createdAt)])
        let all = try context.fetch(descriptor)
        return all
            .filter { $0.deletedAt == nil && range.contains($0.createdAt) }
            .map { appraisal in
                DashboardCalculator.Snapshot(
                    appraisalId: appraisal.id,
                    staffId: appraisal.staffId,
                    staffName: appraisal.staffId,
                    vehicleLabel: "\(masters.makerName(appraisal.vehicle.makerCode)) \(masters.modelName(appraisal.vehicle.modelCode))",
                    status: appraisal.status,
                    aiProposedPrice: appraisal.aiProposedPrice,
                    confirmedPrice: appraisal.confirmedPrice,
                    createdAt: appraisal.createdAt
                )
            }
    }
}
