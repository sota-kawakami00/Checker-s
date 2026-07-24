import SwiftUI

/// 万円区切り・カウントアップアニメーション付き価格表示（03 §2.4/§3）。
/// `accessibilityReduceMotion` 時は即時表示。VoiceOverは「百八十三万円」形式（03 §5）。
public struct PriceLabel: View {
    private let amount: Int
    private let animated: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var priceSize: CGFloat = 40  // ci.priceXL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Int = 0

    public init(amount: Int, animated: Bool = true) {
        self.amount = amount
        self.animated = animated
    }

    public var body: some View {
        Text(PriceFormatting.yen(displayed))
            .font(.system(size: priceSize, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(CIToken.Colors.priceText)
            .contentTransition(.numericText(value: Double(displayed)))
            .accessibilityLabel(Text(PriceFormatting.spokenYen(amount)))
            .onAppear {
                if reduceMotion || !animated {
                    displayed = amount
                } else {
                    displayed = 0
                    withAnimation(.easeOut(duration: 0.8)) {
                        displayed = amount
                    }
                }
            }
            .onChange(of: amount) { _, newValue in
                if reduceMotion || !animated {
                    displayed = newValue
                } else {
                    withAnimation(.easeOut(duration: 0.8)) {
                        displayed = newValue
                    }
                }
            }
    }
}
