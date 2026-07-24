import Foundation
import Core

/// ダッシュボード集計（SCREEN_DASHBOARD.md §15-1: pure に分離してUT先行）。
public enum DashboardCalculator {

    /// 集計対象のスナップショット（SwiftData から供給）
    public struct Snapshot: Sendable, Equatable {
        public var appraisalId: String
        public var staffId: String
        public var staffName: String
        public var vehicleLabel: String
        public var status: AppraisalStatus
        public var aiProposedPrice: Int?
        public var confirmedPrice: Int?
        public var createdAt: Date

        public init(
            appraisalId: String,
            staffId: String,
            staffName: String,
            vehicleLabel: String,
            status: AppraisalStatus,
            aiProposedPrice: Int?,
            confirmedPrice: Int?,
            createdAt: Date
        ) {
            self.appraisalId = appraisalId
            self.staffId = staffId
            self.staffName = staffName
            self.vehicleLabel = vehicleLabel
            self.status = status
            self.aiProposedPrice = aiProposedPrice
            self.confirmedPrice = confirmedPrice
            self.createdAt = createdAt
        }

        var isConfirmedOrLater: Bool {
            status == .confirmed || status == .won || status == .lost || status == .expired
        }
    }

    /// FR-603: 期間別査定件数/確定率/成約率/平均査定額（前期間比付き）
    public static func metrics(
        current: [Snapshot],
        previous: [Snapshot],
        calendar: Calendar = .current
    ) -> DashboardMetrics {
        func rate(_ numerator: Int, _ denominator: Int) -> Double {
            denominator == 0 ? 0 : Double(numerator) / Double(denominator)
        }
        func average(_ values: [Int]) -> Double {
            values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
        }
        func delta(_ now: Double, _ before: Double) -> Double? {
            guard before != 0 else { return nil }
            return (now - before) / before
        }

        let count = Double(current.count)
        let prevCount = Double(previous.count)

        let confirmRate = rate(current.filter(\.isConfirmedOrLater).count, current.count)
        let prevConfirmRate = rate(previous.filter(\.isConfirmedOrLater).count, previous.count)

        let wonRate = rate(current.filter { $0.status == .won }.count, current.count)
        let prevWonRate = rate(previous.filter { $0.status == .won }.count, previous.count)

        let avgPrice = average(current.compactMap { $0.confirmedPrice ?? $0.aiProposedPrice })
        let prevAvgPrice = average(previous.compactMap { $0.confirmedPrice ?? $0.aiProposedPrice })

        // 日別推移（SCREEN_DASHBOARD §2-③）
        let grouped = Dictionary(grouping: current) { calendar.startOfDay(for: $0.createdAt) }
        let daily = grouped.keys.sorted().map { day in
            let snapshots = grouped[day] ?? []
            return DashboardDailyPoint(
                date: day,
                appraisalCount: snapshots.count,
                wonCount: snapshots.filter { $0.status == .won }.count
            )
        }

        return DashboardMetrics(
            appraisalCount: KPIValue(value: count, deltaRate: delta(count, prevCount)),
            confirmRate: KPIValue(value: confirmRate, deltaRate: delta(confirmRate, prevConfirmRate)),
            wonRate: KPIValue(value: wonRate, deltaRate: delta(wonRate, prevWonRate)),
            averageAppraisedPrice: KPIValue(value: avgPrice, deltaRate: delta(avgPrice, prevAvgPrice)),
            daily: daily
        )
    }

    /// FR-603: スタッフ別実績
    public static func staffPerformance(_ snapshots: [Snapshot]) -> [StaffMetrics] {
        Dictionary(grouping: snapshots, by: \.staffId).map { staffId, items in
            let adjustments = items.compactMap { snapshot -> Double? in
                guard let confirmed = snapshot.confirmedPrice, let proposed = snapshot.aiProposedPrice else { return nil }
                return Double(confirmed - proposed)
            }
            return StaffMetrics(
                staffId: staffId,
                displayName: items.first?.staffName ?? staffId,
                appraisalCount: items.count,
                confirmedCount: items.filter(\.isConfirmedOrLater).count,
                wonCount: items.filter { $0.status == .won }.count,
                averageAdjustment: adjustments.isEmpty ? 0 : adjustments.reduce(0, +) / Double(adjustments.count)
            )
        }
        .sorted { $0.appraisalCount > $1.appraisalCount }
    }

    /// FR-604: AI提案額とスタッフ確定額の乖離分析（manager以上）
    /// - Parameter outlierRate: この乖離率以上を「乖離大」として抽出（既定 10%）
    public static func deviationReport(_ snapshots: [Snapshot], outlierRate: Double = 0.1) -> DeviationReport {
        let pairs = snapshots.compactMap { snapshot -> (Snapshot, Int, Int)? in
            guard let confirmed = snapshot.confirmedPrice, let proposed = snapshot.aiProposedPrice, proposed > 0 else { return nil }
            return (snapshot, proposed, confirmed)
        }
        guard !pairs.isEmpty else {
            return DeviationReport(averageDeviation: 0, averageDeviationRate: 0, outliers: [])
        }
        let deviations = pairs.map { Double($0.2 - $0.1) }
        let rates = pairs.map { Double($0.2 - $0.1) / Double($0.1) }
        let outliers = pairs.filter { abs(Double($0.2 - $0.1) / Double($0.1)) >= outlierRate }
            .map { DeviationItem(appraisalId: $0.0.appraisalId, vehicleLabel: $0.0.vehicleLabel, aiProposedPrice: $0.1, confirmedPrice: $0.2) }
            .sorted { abs($0.deviation) > abs($1.deviation) }

        return DeviationReport(
            averageDeviation: deviations.reduce(0, +) / Double(deviations.count),
            averageDeviationRate: rates.reduce(0, +) / Double(rates.count),
            outliers: outliers
        )
    }

    /// 期間 → 日付レンジ（現期間と前期間）
    public static func dateRanges(
        period: DashboardPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (current: Range<Date>, previous: Range<Date>) {
        let startOfToday = calendar.startOfDay(for: now)
        switch period {
        case .today:
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            let prevStart = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? now
            return (startOfToday..<end, prevStart..<startOfToday)
        case .thisWeek:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
            let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
            let prevStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
            return (weekStart..<weekEnd, prevStart..<weekStart)
        case .thisMonth, .custom:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
            let monthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? now
            let prevStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            return (monthStart..<monthEnd, prevStart..<monthStart)
        }
    }
}
