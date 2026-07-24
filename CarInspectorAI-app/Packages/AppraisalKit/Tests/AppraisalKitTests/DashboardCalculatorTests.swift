import Foundation
import Testing
import Core
@testable import AppraisalKit

/// 集計ロジック（SCREEN_DASHBOARD §15-1 / SCR-DASH-04）
@Suite("DashboardCalculator")
struct DashboardCalculatorTests {

    private func snapshot(
        id: String,
        staff: String = "s1",
        status: AppraisalStatus,
        proposed: Int? = nil,
        confirmed: Int? = nil,
        daysAgo: Double = 0
    ) -> DashboardCalculator.Snapshot {
        DashboardCalculator.Snapshot(
            appraisalId: id,
            staffId: staff,
            staffName: staff,
            vehicleLabel: "トヨタ ヴォクシー",
            status: status,
            aiProposedPrice: proposed,
            confirmedPrice: confirmed,
            createdAt: Date(timeIntervalSinceNow: -daysAgo * 86_400)
        )
    }

    @Test("KPI: 件数・確定率・成約率・平均査定額と前期間比")
    func metrics() {
        let current = [
            snapshot(id: "a", status: .confirmed, proposed: 1_000_000, confirmed: 1_000_000),
            snapshot(id: "b", status: .won, proposed: 2_000_000, confirmed: 2_000_000),
            snapshot(id: "c", status: .draft),
            snapshot(id: "d", status: .aiCompleted, proposed: 3_000_000)
        ]
        let previous = [
            snapshot(id: "p1", status: .won, proposed: 1_000_000, confirmed: 1_000_000),
            snapshot(id: "p2", status: .lost, proposed: 1_000_000, confirmed: 1_000_000)
        ]
        let metrics = DashboardCalculator.metrics(current: current, previous: previous)

        #expect(metrics.appraisalCount.value == 4)
        #expect(metrics.appraisalCount.deltaRate == 1.0)          // 2件→4件 = +100%
        #expect(metrics.confirmRate.value == 0.5)                 // 4件中2件（confirmed+won）
        #expect(metrics.wonRate.value == 0.25)
        #expect(metrics.averageAppraisedPrice.value == 2_000_000) // (1M+2M+3M)/3
    }

    @Test("SCR-DASH-04: 乖離計算の符号・平均値（フィクスチャ）")
    func deviation() {
        let snapshots = [
            snapshot(id: "a", status: .confirmed, proposed: 1_000_000, confirmed: 1_100_000),  // +100k (+10%)
            snapshot(id: "b", status: .confirmed, proposed: 2_000_000, confirmed: 1_900_000),  // -100k (-5%)
            snapshot(id: "c", status: .confirmed, proposed: 1_000_000, confirmed: 1_000_000),  // ±0
            snapshot(id: "d", status: .draft)                                                   // 対象外
        ]
        let report = DashboardCalculator.deviationReport(snapshots)

        #expect(report.averageDeviation == 0)                       // (+100k -100k +0)/3
        #expect(abs(report.averageDeviationRate - (0.1 - 0.05) / 3) < 1e-9)
        #expect(report.outliers.count == 1)                         // |乖離率| >= 10% は a のみ
        #expect(report.outliers.first?.appraisalId == "a")
        #expect(report.outliers.first?.deviation == 100_000)
    }

    @Test("スタッフ別実績: 件数・確定・成約・平均調整幅")
    func staffPerformance() {
        let snapshots = [
            snapshot(id: "a", staff: "s1", status: .won, proposed: 1_000_000, confirmed: 1_050_000),
            snapshot(id: "b", staff: "s1", status: .confirmed, proposed: 1_000_000, confirmed: 950_000),
            snapshot(id: "c", staff: "s2", status: .draft)
        ]
        let performance = DashboardCalculator.staffPerformance(snapshots)

        #expect(performance.count == 2)
        let s1 = performance.first { $0.staffId == "s1" }
        #expect(s1?.appraisalCount == 2)
        #expect(s1?.confirmedCount == 2)
        #expect(s1?.wonCount == 1)
        #expect(s1?.averageAdjustment == 0)  // (+50k, -50k)
    }

    @Test("SCR-DASH-03: 0件期間は空のKPI")
    func emptyPeriod() {
        let metrics = DashboardCalculator.metrics(current: [], previous: [])
        #expect(metrics.appraisalCount.value == 0)
        #expect(metrics.appraisalCount.deltaRate == nil)
        #expect(metrics.daily.isEmpty)
    }
}
