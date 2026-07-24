import SwiftUI

/// 加減点1行（アイコン/項目名/±金額/根拠リンク、03 §2.4）。
/// 加点は accent、減点は danger。色だけに依存せず ± 記号を必ず併記（NFR-10）。
public struct AdjustmentRow: View {
    private let label: String
    private let amount: Int
    private let hasEvidence: Bool
    private let onTapEvidence: (() -> Void)?

    public init(label: String, amount: Int, hasEvidence: Bool = false, onTapEvidence: (() -> Void)? = nil) {
        self.label = label
        self.amount = amount
        self.hasEvidence = hasEvidence
        self.onTapEvidence = onTapEvidence
    }

    private var color: Color {
        amount >= 0 ? CIToken.Colors.accent : CIToken.Colors.danger
    }

    public var body: some View {
        HStack(spacing: CIToken.Space.s) {
            Image(systemName: amount >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(color)
            Text(label)
                .font(CIToken.Fonts.body)
            Spacer(minLength: CIToken.Space.s)
            Text(PriceFormatting.signedYen(amount))
                .font(CIToken.Fonts.mono.bold())
                .foregroundStyle(color)
            if hasEvidence {
                Button {
                    onTapEvidence?()
                } label: {
                    Image(systemName: "photo.circle")
                        .foregroundStyle(CIToken.Colors.primary)
                }
                .accessibilityLabel(Text(L10n.string("adjustment.evidence.a11y")))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenSummary))
    }

    /// 「加点 人気カラー 五万円」形式（03 §5）
    private var spokenSummary: String {
        let kind = L10n.string(amount >= 0 ? "adjustment.plus" : "adjustment.minus")
        return "\(kind) \(label) \(PriceFormatting.spokenYen(abs(amount)))"
    }
}
