import SwiftUI
import Core
import AppraisalKit
import DesignSystem

/// 査定結果画面（SCREEN_APPRAISAL_RESULT.md）。Running/結果は同一Viewの phase 分岐。
struct AppraisalResultView: View {
    let appraisalId: String
    @Binding var path: [Route]

    @Environment(\.appContainer) private var container
    @State private var viewModel: AppraisalResultViewModel?
    @State private var evidencePhotoId: String?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .background(CIToken.Colors.bgBase)
        .navigationTitle(Text("result.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = AppraisalResultViewModel(
                    appraisalService: container.appraisalService,
                    pdfService: container.pdfService,
                    auth: container.authService,
                    masters: container.masters
                )
            }
            await viewModel?.observe(appraisalId: appraisalId)
        }
    }

    @ViewBuilder
    private func content(_ viewModel: AppraisalResultViewModel) -> some View {
        @Bindable var viewModel = viewModel
        switch viewModel.phase {
        case .running:
            RunningView(viewModel: viewModel)
        case .failed:
            failedView(viewModel)
        case .reviewing, .confirmed:
            reviewView(viewModel)
                .sheet(isPresented: $viewModel.isAdjustSheetPresented) {
                    AdjustPriceSheet(viewModel: viewModel)
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $viewModel.isManagerApprovalPresented) {
                    ManagerApprovalSheet(viewModel: viewModel)
                        .presentationDetents([.medium])
                }
                .sheet(item: Binding(
                    get: { evidencePhotoId.map(EvidenceSheetItem.init(photoId:)) },
                    set: { evidencePhotoId = $0?.photoId }
                )) { item in
                    EvidencePhotoViewer(
                        photoPath: viewModel.photoPath(for: item.photoId),
                        evidences: viewModel.result?.repairFinding.evidences.filter { $0.photoId == item.photoId } ?? []
                    )
                }
        }
    }

    private struct EvidenceSheetItem: Identifiable {
        let photoId: String
        var id: String { photoId }
    }

    // MARK: - 2.1 Running

    private func failedView(_ viewModel: AppraisalResultViewModel) -> some View {
        VStack(spacing: CIToken.Space.l) {
            EmptyStateView(
                systemImage: "exclamationmark.arrow.circlepath",
                title: String(localized: "result.failed.title"),
                message: failureMessage(viewModel)
            )
            VStack(spacing: CIToken.Space.s) {
                PrimaryButton(String(localized: "result.retry")) {
                    Task { await viewModel.retryAI() }
                }
                SecondaryButton(String(localized: "result.later")) {
                    path.removeAll()
                }
            }
            .padding(.horizontal, CIToken.Space.xl)
        }
    }

    private func failureMessage(_ viewModel: AppraisalResultViewModel) -> String {
        switch viewModel.appraisal?.aiFailureReason {
        case "quota": String(localized: "result.failed.quota")
        case "aiInvalidResponse": String(localized: "result.failed.invalid")
        default: String(localized: "result.failed.generic")
        }
    }

    // MARK: - 2.2 結果ビュー

    private func reviewView(_ viewModel: AppraisalResultViewModel) -> some View {
        ScrollView {
            VStack(spacing: CIToken.Space.m) {
                priceCard(viewModel)

                // ④ 修復歴カード: probability>=0.5 は内訳の上に昇格（§2-④）
                if viewModel.repairSuspected {
                    repairCard(viewModel)
                }
                breakdownCard(viewModel)
                marketCard(viewModel)
                if !viewModel.repairSuspected, viewModel.result?.repairFinding.probability ?? 0 > 0 {
                    repairCard(viewModel)
                }
                completenessCard(viewModel)
            }
            .padding(CIToken.Space.m)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar(viewModel)
        }
        .sensoryFeedback(.warning, trigger: viewModel.repairSuspected)
        // 確定/PDF共有後は Home へ戻る（02 §4 状態遷移: AppraisalResult --> Home）
        .toolbar {
            if viewModel.phase == .confirmed {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        path.removeAll()
                    }
                    .accessibilityIdentifier("result.done")
                }
            }
        }
    }

    // ① 価格カード（glassStrong: 可読性最優先）
    private func priceCard(_ viewModel: AppraisalResultViewModel) -> some View {
        GlassCard(strong: true) {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                HStack {
                    Text(viewModel.vehicleLabel)
                        .font(CIToken.Fonts.body.bold())
                    Spacer()
                    if viewModel.phase == .confirmed, let status = viewModel.appraisal?.status {
                        StatusChip(status: status)
                    }
                }
                Text("result.price.label")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
                PriceLabel(amount: viewModel.appraisal?.confirmedPrice ?? viewModel.result?.appraisedPrice ?? 0)

                HStack(spacing: CIToken.Space.m) {
                    if let tradeIn = viewModel.result?.tradeInReference {
                        Text("result.tradeIn \(PriceFormatting.yen(tradeIn))")
                            .font(CIToken.Fonts.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let confidence = viewModel.appraisal?.aiConfidence {
                        ConfidenceBadge(confidence: confidence)
                    }
                }

                if viewModel.result?.needsReview == true {
                    Label("result.needsReview", systemImage: "exclamationmark.triangle.fill")
                        .font(CIToken.Fonts.caption.bold())
                        .foregroundStyle(CIToken.Colors.warning)
                }
            }
        }
    }

    // ② 根拠カード「査定の内訳」（内訳行は60ms間隔フェードイン §11）
    private func breakdownCard(_ viewModel: AppraisalResultViewModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                Text("result.breakdown.title")
                    .font(CIToken.Fonts.titleL)
                if let result = viewModel.result {
                    HStack {
                        Text("result.breakdown.base")
                            .font(CIToken.Fonts.body)
                        Spacer()
                        Text(PriceFormatting.yen(result.basePrice))
                            .font(CIToken.Fonts.mono.bold())
                    }
                    Divider()
                    ForEach(Array(result.adjustments.enumerated()), id: \.element.id) { index, adjustment in
                        AdjustmentRow(
                            label: adjustment.label,
                            amount: adjustment.amount,
                            hasEvidence: !adjustment.evidencePhotoIds.isEmpty
                        ) {
                            evidencePhotoId = adjustment.evidencePhotoIds.first
                        }
                        .transition(.opacity)
                        .animation(.easeIn(duration: 0.25).delay(Double(index) * 0.06), value: viewModel.phase)
                    }
                    Divider()
                    HStack {
                        Text("result.breakdown.total")
                            .font(CIToken.Fonts.body.bold())
                        Spacer()
                        Text(PriceFormatting.yen(result.appraisedPrice))
                            .font(CIToken.Fonts.mono.bold())
                    }
                }
            }
        }
    }

    // ③ 市場比較カード
    private func marketCard(_ viewModel: AppraisalResultViewModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                Text("result.market.title")
                    .font(CIToken.Fonts.titleL)
                if let result = viewModel.result {
                    HStack {
                        Text("result.market.average")
                        Spacer()
                        Text(PriceFormatting.yen(result.marketAveragePrice))
                            .font(CIToken.Fonts.mono)
                    }
                    if let deviation = viewModel.marketDeviationRate {
                        HStack {
                            Text("result.market.deviation")
                            Spacer()
                            Text(verbatim: String(format: "%+.1f%%", deviation * 100))
                                .font(CIToken.Fonts.mono)
                                .foregroundStyle(abs(deviation) > 0.15 ? CIToken.Colors.warning : .secondary)
                        }
                    }
                    marketPositionBar(result)
                        .accessibilityLabel(Text("result.market.position.a11y"))
                }
            }
        }
    }

    /// 分布バー（p25-p75 と自車位置。テキスト代替付き §13）
    private func marketPositionBar(_ result: AppraisalResult) -> some View {
        GeometryReader { proxy in
            let low = Double(result.marketAveragePrice) * 0.75
            let high = Double(result.marketAveragePrice) * 1.25
            let ratio = max(0, min(1, (Double(result.appraisedPrice) - low) / max(1, high - low)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                Capsule()
                    .fill(CIToken.Colors.primary.opacity(0.35))
                    .frame(width: proxy.size.width * 0.5, height: 8)
                    .offset(x: proxy.size.width * 0.25)
                Circle()
                    .fill(CIToken.Colors.primary)
                    .frame(width: 16, height: 16)
                    .offset(x: proxy.size.width * ratio - 8)
            }
        }
        .frame(height: 16)
    }

    // ④ 修復歴カード（danger 枠、§2-④ / UC-03）
    private func repairCard(_ viewModel: AppraisalResultViewModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                Label {
                    Text("result.repair.title \(Int((viewModel.appraisal?.repairProbability ?? 0) * 100))")
                        .font(CIToken.Fonts.titleL)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(viewModel.repairSuspected ? CIToken.Colors.danger : .primary)

                if let evidences = viewModel.result?.repairFinding.evidences, !evidences.isEmpty {
                    ForEach(evidences) { evidence in
                        Button {
                            evidencePhotoId = evidence.photoId
                        } label: {
                            HStack {
                                Image(systemName: "photo")
                                VStack(alignment: .leading) {
                                    Text(LocalizedStringKey("repair.type.\(evidence.type.rawValue)"))
                                        .font(CIToken.Fonts.body.bold())
                                    Text(evidence.note)
                                        .font(CIToken.Fonts.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.repairSuspected {
                    Text("result.repair.confirmPrompt")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(.secondary)
                    // 現車確認（未選択なら確定不可 UC-03）
                    HStack(spacing: CIToken.Space.s) {
                        repairChoice(viewModel, state: .confirmedYes, key: "result.repair.yes")
                        repairChoice(viewModel, state: .confirmedNo, key: "result.repair.no")
                        repairChoice(viewModel, state: .unknown, key: "result.repair.unknown")
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: CIToken.Radius.card)
                .strokeBorder(viewModel.repairSuspected ? CIToken.Colors.danger : .clear, lineWidth: 2)
        )
    }

    private func repairChoice(_ viewModel: AppraisalResultViewModel, state: RepairConfirmedState, key: LocalizedStringKey) -> some View {
        let isSelected = viewModel.appraisal?.repairConfirmedState == state
        return Button {
            Task { await viewModel.setRepairConfirmed(state) }
        } label: {
            Text(key)
                .font(CIToken.Fonts.caption.bold())
                .padding(.vertical, CIToken.Space.s)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? CIToken.Colors.danger.opacity(0.2) : Color.gray.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? CIToken.Colors.danger : .primary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.phase == .confirmed)
    }

    // ⑤ 査定品質カード（チェックONで即時再計算 §2-⑤）
    private func completenessCard(_ viewModel: AppraisalResultViewModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CIToken.Space.s) {
                HStack {
                    Text("result.completeness.title")
                        .font(CIToken.Fonts.titleL)
                    Spacer()
                    Text(verbatim: "\(Int((viewModel.appraisal?.completenessScore ?? 0) * 100))%")
                        .font(CIToken.Fonts.mono.bold())
                        .contentTransition(.numericText())
                }
                ForEach(viewModel.allCheckItemCodes, id: \.self) { code in
                    let unchecked = viewModel.appraisal?.uncheckedItems.contains(code) ?? false
                    Button {
                        Task { await viewModel.toggleCheckItem(code) }
                    } label: {
                        HStack {
                            Image(systemName: unchecked ? "square" : "checkmark.square.fill")
                                .foregroundStyle(unchecked ? Color.secondary : CIToken.Colors.accent)
                            VStack(alignment: .leading) {
                                Text(viewModel.checkItemLabel(code))
                                    .font(CIToken.Fonts.body)
                                if unchecked {
                                    Text(viewModel.checkItemHint(code))
                                        .font(CIToken.Fonts.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ⑥ 操作エリア（下部固定 glass）
    private func actionBar(_ viewModel: AppraisalResultViewModel) -> some View {
        VStack(spacing: CIToken.Space.s) {
            if let reasonKey = viewModel.confirmBlockReasonKey {
                Text(LocalizedStringKey(reasonKey))
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(CIToken.Colors.warning)
            }
            if viewModel.phase == .confirmed {
                HStack(spacing: CIToken.Space.s) {
                    PrimaryButton(String(localized: "result.pdf"), isLoading: viewModel.isGeneratingPDF) {
                        Task { _ = await viewModel.generatePDF() }
                    }
                    .accessibilityIdentifier("result.pdf")
                    if let url = viewModel.pdfURL {
                        ShareLink(item: url) {
                            Label("result.share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: CIToken.Radius.button))
                    }
                }
            } else {
                HStack(spacing: CIToken.Space.s) {
                    SecondaryButton(String(localized: "result.adjust")) {
                        viewModel.isAdjustSheetPresented = true
                    }
                    .accessibilityIdentifier("result.adjust")
                    PrimaryButton(String(localized: "result.confirm"), isEnabled: viewModel.canConfirm || viewModel.confirmBlockers == [.lowConfidenceNeedsManager]) {
                        Task { await viewModel.confirm() }
                    }
                    .accessibilityIdentifier("result.confirm")
                    .accessibilityHint(viewModel.confirmBlockReasonKey.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: ""))
                }
            }
        }
        .padding(CIToken.Space.m)
        .background(CIToken.Materials.glass)
    }
}

/// Running（解析中）ビュー（§2.1）
private struct RunningView: View {
    let viewModel: AppraisalResultViewModel

    private static let messages: [LocalizedStringKey] = [
        "result.running.analyzing",
        "result.running.market",
        "result.running.calculating"
    ]

    var body: some View {
        VStack(spacing: CIToken.Space.l) {
            ZStack {
                Circle()
                    .stroke(CIToken.Colors.primary.opacity(0.2), lineWidth: 8)
                    .frame(width: 140, height: 140)
                ProgressView()
                    .controlSize(.large)
                Image(systemName: "car.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(CIToken.Colors.primary)
                    .offset(y: 0)
            }
            Text(viewModel.isOverThirtySeconds ? "result.running.busy" : Self.messages[viewModel.progressMessageIndex])
                .font(CIToken.Fonts.body)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: viewModel.progressMessageIndex)
            Text("result.running.hint")
                .font(CIToken.Fonts.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
