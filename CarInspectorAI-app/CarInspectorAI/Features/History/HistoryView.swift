import SwiftUI
import Core
import DesignSystem

/// 査定履歴（SCREEN_HISTORY.md）
struct HistoryView: View {
    @Binding var path: [Route]

    @Environment(\.appContainer) private var container
    @State private var viewModel: HistoryViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .navigationTitle(Text("history.title"))
        .task {
            if viewModel == nil {
                viewModel = HistoryViewModel(appraisalService: container.appraisalService, auth: container.authService)
            }
            await viewModel?.reload()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HistoryViewModel) -> some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            filterBar(viewModel)

            switch viewModel.phase {
            case .loading:
                List {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonCard()
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            case .empty:
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: String(localized: "history.empty.title"),
                    message: String(localized: emptyMessageKey(viewModel))
                )
            case .content:
                list(viewModel)
            }
        }
        // リストは標準リスト（大量表示のためガラス効果なし §12）
        .searchable(text: $viewModel.searchText, prompt: Text("history.search.prompt"))
    }

    private func emptyMessageKey(_ viewModel: HistoryViewModel) -> String.LocalizationValue {
        if !viewModel.searchText.isEmpty { return "history.empty.search" }
        if viewModel.statusFilter != nil || viewModel.repairSuspectedOnly { return "history.empty.filtered" }
        return "history.empty.message"
    }

    /// ② フィルタチップ（フィルタバーのみ glass §12）
    private func filterBar(_ viewModel: HistoryViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CIToken.Space.s) {
                Menu {
                    Button("history.filter.period.all") { viewModel.periodDays = nil }
                    Button("history.filter.period.7d") { viewModel.periodDays = 7 }
                    Button("history.filter.period.30d") { viewModel.periodDays = 30 }
                    Button("history.filter.period.90d") { viewModel.periodDays = 90 }
                } label: {
                    chipLabel(
                        viewModel.periodDays == nil
                            ? String(localized: "history.filter.period")
                            : String(localized: "history.filter.period.days \(viewModel.periodDays ?? 0)"),
                        active: viewModel.periodDays != nil
                    )
                }

                Menu {
                    Button("history.filter.status.all") { viewModel.statusFilter = nil }
                    ForEach(AppraisalStatus.allCases, id: \.self) { status in
                        Button {
                            viewModel.statusFilter = status
                        } label: {
                            StatusChip(status: status)
                        }
                    }
                } label: {
                    chipLabel(String(localized: "history.filter.status"), active: viewModel.statusFilter != nil)
                }

                Toggle(isOn: $viewModel.mineOnly) {
                    Text("history.filter.mine")
                        .font(CIToken.Fonts.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)

                Toggle(isOn: $viewModel.repairSuspectedOnly) {
                    Text("history.filter.repair")
                        .font(CIToken.Fonts.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(CIToken.Colors.danger)
            }
            .padding(.horizontal, CIToken.Space.m)
            .padding(.vertical, CIToken.Space.s)
        }
        .background(CIToken.Materials.glass)
    }

    private func chipLabel(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(CIToken.Fonts.caption)
            .padding(.horizontal, CIToken.Space.s)
            .padding(.vertical, CIToken.Space.xs)
            .background(active ? CIToken.Colors.primary.opacity(0.15) : Color.gray.opacity(0.1), in: Capsule())
            .foregroundStyle(active ? CIToken.Colors.primary : .primary)
    }

    // ③ リスト（50件ページング）
    private func list(_ viewModel: HistoryViewModel) -> some View {
        List {
            ForEach(viewModel.items, id: \.id) { appraisal in
                row(appraisal, viewModel: viewModel)
                    .listRowSeparator(.visible)
                    // ④ 行スワイプ: 複製 / 成約 / 失注（Rotor対応は combine 済み要素で提供）
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task {
                                if let draftId = await viewModel.duplicate(id: appraisal.id) {
                                    path.append(.vehicleInfo(draftId: draftId))
                                }
                            }
                        } label: {
                            Label("history.duplicate", systemImage: "doc.on.doc")
                        }
                        .tint(CIToken.Colors.primary)

                        if appraisal.status == .confirmed {
                            Button {
                                Task { await viewModel.markWon(id: appraisal.id) }
                            } label: {
                                Label("history.won", systemImage: "checkmark.seal")
                            }
                            .tint(CIToken.Colors.accent)

                            Button {
                                Task { await viewModel.markLost(id: appraisal.id) }
                            } label: {
                                Label("history.lost", systemImage: "xmark.seal")
                            }
                            .tint(.gray)
                        }
                    }
                    .onAppear {
                        if appraisal.id == viewModel.items.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.reload()
        }
    }

    private func row(_ appraisal: Appraisal, viewModel: HistoryViewModel) -> some View {
        Button {
            path.append(.historyDetail(appraisalId: appraisal.id))
        } label: {
            HStack(spacing: CIToken.Space.s) {
                thumbnail(appraisal)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: CIToken.Space.xs) {
                        Text(viewModel.vehicleLabel(appraisal))
                            .font(CIToken.Fonts.body.bold())
                            .lineLimit(1)
                        if let year = appraisal.vehicle.modelYear {
                            Text(verbatim: "\(year)年")
                                .font(CIToken.Fonts.caption)
                                .foregroundStyle(.secondary)
                        }
                        // 期限切れ間近 warning ドット（SCR-HIS-04）
                        if viewModel.isExpiringSoon(appraisal) {
                            Circle()
                                .fill(CIToken.Colors.warning)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel(Text("history.expiringSoon"))
                        }
                    }
                    if let price = appraisal.confirmedPrice ?? appraisal.aiProposedPrice {
                        Text(PriceFormatting.yen(price))
                            .font(CIToken.Fonts.mono)
                    }
                    HStack(spacing: CIToken.Space.s) {
                        Text(appraisal.createdAt, format: .dateTime.month().day())
                        Text(appraisal.staffId)
                    }
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(status: appraisal.status)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func thumbnail(_ appraisal: Appraisal) -> some View {
        if let photoPath = appraisal.photos.first?.localMaskedPath,
           let uiImage = UIImage(contentsOfFile: photoPath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 56, height: 42)
                .overlay {
                    Image(systemName: "car.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
