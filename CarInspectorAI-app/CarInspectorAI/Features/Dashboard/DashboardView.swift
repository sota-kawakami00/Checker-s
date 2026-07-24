import SwiftUI
import Charts
import Core
import DesignSystem

/// 店舗ダッシュボード（SCREEN_DASHBOARD.md）
struct DashboardView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: DashboardViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .background(CIToken.Colors.bgBase)
        .navigationTitle(Text("dashboard.title"))
        .task {
            if viewModel == nil {
                viewModel = DashboardViewModel(dashboardService: container.dashboardService, auth: container.authService)
            }
            await viewModel?.reload()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: CIToken.Space.m) {
                // ① 期間セグメント
                Picker("dashboard.period", selection: $viewModel.period) {
                    Text("dashboard.period.today").tag(DashboardPeriod.today)
                    Text("dashboard.period.week").tag(DashboardPeriod.thisWeek)
                    Text("dashboard.period.month").tag(DashboardPeriod.thisMonth)
                }
                .pickerStyle(.segmented)

                switch viewModel.phase {
                case .loading:
                    // スケルトンKPI（§3）
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CIToken.Space.m) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonCard()
                        }
                    }
                case .empty:
                    EmptyStateView(
                        systemImage: "chart.bar",
                        title: String(localized: "dashboard.empty.title"),
                        message: String(localized: "dashboard.empty.message")
                    )
                    .frame(minHeight: 320)
                case .content:
                    if let metrics = viewModel.metrics {
                        kpiGrid(metrics)
                        trendChart(metrics)
                    } else if viewModel.metricsError {
                        errorCard("dashboard.error.metrics")
                    }

                    staffTable(viewModel)

                    if viewModel.showsDeviation {
                        deviationCard(viewModel)
                    }
                }
            }
            .padding(CIToken.Space.m)
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    // ② KPIカード4枚（前期間比 ▲▼%）
    private func kpiGrid(_ metrics: DashboardMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CIToken.Space.m) {
            kpiCard(titleKey: "dashboard.kpi.count", value: String(Int(metrics.appraisalCount.value)), delta: metrics.appraisalCount.deltaRate)
            kpiCard(titleKey: "dashboard.kpi.confirmRate", value: percent(metrics.confirmRate.value), delta: metrics.confirmRate.deltaRate)
            kpiCard(titleKey: "dashboard.kpi.wonRate", value: percent(metrics.wonRate.value), delta: metrics.wonRate.deltaRate)
            kpiCard(titleKey: "dashboard.kpi.avgPrice", value: PriceFormatting.yen(Int(metrics.averageAppraisedPrice.value)), delta: metrics.averageAppraisedPrice.deltaRate)
        }
    }

    private func kpiCard(titleKey: LocalizedStringKey, value: String, delta: Double?) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.xs) {
                Text(titleKey)
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title2, design: .rounded).bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let delta {
                    Label {
                        Text(verbatim: String(format: "%.0f%%", abs(delta) * 100))
                    } icon: {
                        Image(systemName: delta >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    }
                    .font(CIToken.Fonts.caption.bold())
                    .foregroundStyle(delta >= 0 ? CIToken.Colors.accent : CIToken.Colors.danger)
                } else {
                    Text("dashboard.kpi.noComparison")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // ③ 推移チャート（件数+成約の複合、日別。audio graph は Swift Charts 標準）
    private func trendChart(_ metrics: DashboardMetrics) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                Text("dashboard.chart.title")
                    .font(CIToken.Fonts.titleL)
                if metrics.daily.isEmpty {
                    Text("dashboard.chart.empty")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(metrics.daily) { point in
                        BarMark(
                            x: .value("日", point.date, unit: .day),
                            y: .value("査定件数", point.appraisalCount)
                        )
                        .foregroundStyle(CIToken.Colors.primary.opacity(0.6))
                        LineMark(
                            x: .value("日", point.date, unit: .day),
                            y: .value("成約", point.wonCount)
                        )
                        .foregroundStyle(CIToken.Colors.accent)
                        .symbol(.circle)
                    }
                    .frame(height: 180)
                    .accessibilityLabel(Text("dashboard.chart.a11y"))
                }
            }
        }
    }

    // ④ スタッフ別テーブル（staff は自分のみ 06 §4）
    private func staffTable(_ viewModel: DashboardViewModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                Text(viewModel.isManager ? "dashboard.staff.title" : "dashboard.staff.mine")
                    .font(CIToken.Fonts.titleL)
                if viewModel.staffError {
                    Text("dashboard.error.staff")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(CIToken.Colors.danger)
                } else if viewModel.staffMetrics.isEmpty {
                    Text("dashboard.staff.empty")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, verticalSpacing: CIToken.Space.s) {
                        GridRow {
                            Text("dashboard.staff.name")
                            Text("dashboard.staff.count")
                            Text("dashboard.staff.confirmed")
                            Text("dashboard.staff.won")
                            Text("dashboard.staff.adjustment")
                        }
                        .font(CIToken.Fonts.caption.bold())
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(viewModel.staffMetrics) { staff in
                            GridRow {
                                Text(staff.displayName)
                                    .lineLimit(1)
                                Text(String(staff.appraisalCount))
                                Text(String(staff.confirmedCount))
                                Text(String(staff.wonCount))
                                Text(PriceFormatting.signedYen(Int(staff.averageAdjustment)))
                                    .foregroundStyle(staff.averageAdjustment >= 0 ? CIToken.Colors.accent : CIToken.Colors.danger)
                            }
                            .font(CIToken.Fonts.mono)
                        }
                    }
                }
            }
        }
    }

    // ⑤ AI乖離カード（FR-604, manager+）
    private func deviationCard(_ viewModel: DashboardViewModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                Text("dashboard.deviation.title")
                    .font(CIToken.Fonts.titleL)
                if viewModel.deviationError {
                    Text("dashboard.error.deviation")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(CIToken.Colors.danger)
                } else if let deviation = viewModel.deviation {
                    HStack {
                        Text("dashboard.deviation.average")
                        Spacer()
                        Text(PriceFormatting.signedYen(Int(deviation.averageDeviation)))
                            .font(CIToken.Fonts.mono.bold())
                    }
                    HStack {
                        Text("dashboard.deviation.rate")
                        Spacer()
                        Text(verbatim: String(format: "%+.1f%%", deviation.averageDeviationRate * 100))
                            .font(CIToken.Fonts.mono)
                    }
                    if !deviation.outliers.isEmpty {
                        Divider()
                        Text("dashboard.deviation.outliers")
                            .font(CIToken.Fonts.caption.bold())
                        ForEach(deviation.outliers.prefix(5)) { outlier in
                            HStack {
                                Text(outlier.vehicleLabel)
                                    .font(CIToken.Fonts.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(PriceFormatting.signedYen(outlier.deviation))
                                    .font(CIToken.Fonts.mono)
                                    .foregroundStyle(outlier.deviation >= 0 ? CIToken.Colors.accent : CIToken.Colors.danger)
                            }
                        }
                    }
                }
            }
        }
    }

    private func errorCard(_ key: LocalizedStringKey) -> some View {
        GlassCard {
            Label(key, systemImage: "exclamationmark.triangle")
                .font(CIToken.Fonts.caption)
                .foregroundStyle(CIToken.Colors.danger)
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
