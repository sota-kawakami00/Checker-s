import SwiftUI
import Core
import DesignSystem

/// ホーム（SCREEN_HOME.md）
struct HomeView: View {
    @Binding var path: [Route]
    @Environment(\.appContainer) private var container
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .background(CIToken.Colors.bgBase)
        .navigationTitle(Text("app.name"))
        .task {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    appraisalService: container.appraisalService,
                    syncService: container.syncService,
                    auth: container.authService,
                    storeName: container.store.name
                )
            }
            await viewModel?.onAppear()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        VStack(spacing: 0) {
            // ⑥ OfflineBanner（オフライン時最上部固定、キュー件数表示）
            if !viewModel.queueStatus.isOnline {
                OfflineBanner(queuedCount: viewModel.queueStatus.totalQueued)
            }

            switch viewModel.phase {
            case .loading:
                ScrollView {
                    VStack(spacing: CIToken.Space.m) {
                        SkeletonCard()
                        SkeletonCard()
                        SkeletonCard()
                    }
                    .padding(CIToken.Space.m)
                }
            case .empty:
                // 初回: 空状態（SCR-HOME-03）
                VStack(spacing: CIToken.Space.l) {
                    greeting(viewModel)
                    EmptyStateView(
                        systemImage: "car.2.fill",
                        title: String(localized: "home.empty.title"),
                        message: String(localized: "home.empty.message"),
                        ctaTitle: String(localized: "home.newAppraisal")
                    ) {
                        path.append(.vehicleInfo(draftId: nil))
                    }
                }
                .padding(CIToken.Space.m)
            case .content:
                ScrollView {
                    VStack(alignment: .leading, spacing: CIToken.Space.l) {
                        greeting(viewModel)

                        // ② 新規査定（最重要CTA: primary塗り、ガラスにしない）
                        PrimaryButton(String(localized: "home.newAppraisal")) {
                            path.append(.vehicleInfo(draftId: nil))
                        }
                        .accessibilityIdentifier("home.new")

                        // ③ 進行中カード横スクロール
                        if !viewModel.inProgress.isEmpty {
                            Text("home.inProgress")
                                .font(CIToken.Fonts.titleL)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: CIToken.Space.m) {
                                    ForEach(viewModel.inProgress, id: \.id) { appraisal in
                                        inProgressCard(appraisal, viewModel: viewModel)
                                    }
                                }
                            }
                        }

                        // ④ 最近の確定 3件
                        if !viewModel.recentConfirmed.isEmpty {
                            Text("home.recentConfirmed")
                                .font(CIToken.Fonts.titleL)
                            ForEach(viewModel.recentConfirmed, id: \.id) { appraisal in
                                recentRow(appraisal, viewModel: viewModel)
                            }
                        }
                    }
                    .padding(CIToken.Space.m)
                }
                .refreshable {
                    await viewModel.reload()
                }
            }
        }
    }

    // ① あいさつ + 店舗名 + 本日の査定数
    private func greeting(_ viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: CIToken.Space.xs) {
            Text("home.greeting \(viewModel.staffName)")
                .font(CIToken.Fonts.titleL)
            Text("home.todayCount \(viewModel.storeName) \(viewModel.todayCount)")
                .font(CIToken.Fonts.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inProgressCard(_ appraisal: Appraisal, viewModel: HomeViewModel) -> some View {
        Button {
            switch appraisal.status {
            case .draft:
                path.append(.vehicleInfo(draftId: appraisal.id))
            default:
                path.append(.appraisalResult(appraisalId: appraisal.id))
            }
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: CIToken.Space.s) {
                    HStack {
                        photoThumbnail(appraisal)
                        VStack(alignment: .leading) {
                            Text(viewModel.vehicleLabel(appraisal))
                                .font(CIToken.Fonts.body.bold())
                                .lineLimit(1)
                            Text(appraisal.createdAt, style: .relative)
                                .font(CIToken.Fonts.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: CIToken.Space.s) {
                        if appraisal.status == .aiRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        StatusChip(status: appraisal.status)
                        if viewModel.needsAttention(appraisal) {
                            Label("home.needsAttention", systemImage: "exclamationmark.triangle.fill")
                                .font(CIToken.Fonts.caption.bold())
                                .foregroundStyle(CIToken.Colors.warning)
                        }
                    }
                }
            }
            .frame(width: 250)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func recentRow(_ appraisal: Appraisal, viewModel: HomeViewModel) -> some View {
        Button {
            path.append(.historyDetail(appraisalId: appraisal.id))
        } label: {
            GlassCard {
                HStack {
                    photoThumbnail(appraisal)
                    VStack(alignment: .leading) {
                        Text(viewModel.vehicleLabel(appraisal))
                            .font(CIToken.Fonts.body.bold())
                        if let price = appraisal.confirmedPrice {
                            Text(PriceFormatting.yen(price))
                                .font(CIToken.Fonts.mono)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusChip(status: appraisal.status)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func photoThumbnail(_ appraisal: Appraisal) -> some View {
        if let path = appraisal.photos.first(where: { $0.angle == .front })?.localMaskedPath ?? appraisal.photos.first?.localMaskedPath,
           let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 42)
                .overlay {
                    Image(systemName: "car.fill")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
