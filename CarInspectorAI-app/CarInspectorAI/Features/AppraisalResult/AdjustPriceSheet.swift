import SwiftUI
import DesignSystem

/// 価格調整シート（SCREEN_APPRAISAL_RESULT §2: ステッパー1万円単位 BR-01 + 理由必須 FR-407）
struct AdjustPriceSheet: View {
    @Bindable var viewModel: AppraisalResultViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CIToken.Space.l) {
                    VStack(alignment: .leading, spacing: CIToken.Space.s) {
                        Text("adjust.current")
                            .font(CIToken.Fonts.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                viewModel.adjustPrice(by: -10_000)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(CIToken.Colors.danger)
                            }
                            .accessibilityLabel(Text("adjust.minus10k"))
                            Spacer()
                            Text(PriceFormatting.yen(viewModel.effectivePrice))
                                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                            Spacer()
                            Button {
                                viewModel.adjustPrice(by: 10_000)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(CIToken.Colors.accent)
                            }
                            .accessibilityLabel(Text("adjust.plus10k"))
                        }

                        // AI提案額との差分を常時表示
                        HStack {
                            Text("adjust.aiDiff")
                                .font(CIToken.Fonts.caption)
                            Text(PriceFormatting.signedYen(viewModel.priceDiffFromAI))
                                .font(CIToken.Fonts.mono.bold())
                                .foregroundStyle(
                                    viewModel.priceDiffFromAI == 0
                                        ? Color.secondary
                                        : (viewModel.priceDiffFromAI > 0 ? CIToken.Colors.accent : CIToken.Colors.danger)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: CIToken.Space.s) {
                        Text("adjust.reason")
                            .font(CIToken.Fonts.body.bold())
                        Text("adjust.reason.hint")
                            .font(CIToken.Fonts.caption)
                            .foregroundStyle(.secondary)
                        TextField("adjust.reason.placeholder", text: $viewModel.adjustmentReason, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(CIToken.Space.s)
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: CIToken.Radius.button))
                    }

                    PrimaryButton(String(localized: "adjust.save"), isEnabled: viewModel.canSaveAdjustment) {
                        dismiss()
                    }
                }
                .padding(CIToken.Space.m)
            }
            .navigationTitle(Text("adjust.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        viewModel.adjustedPrice = nil
                        viewModel.adjustmentReason = ""
                        dismiss()
                    }
                }
            }
        }
    }
}

/// manager 承認シート（BR-03: 信頼度<60% の確定は manager 権限で実施）
struct ManagerApprovalSheet: View {
    @Bindable var viewModel: AppraisalResultViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: CIToken.Space.l) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(CIToken.Colors.warning)
                Text("approval.message")
                    .font(CIToken.Fonts.body)
                    .multilineTextAlignment(.center)
                Text("approval.hint")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SecondaryButton(String(localized: "common.close")) {
                    dismiss()
                }
            }
            .padding(CIToken.Space.l)
            .navigationTitle(Text("approval.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
