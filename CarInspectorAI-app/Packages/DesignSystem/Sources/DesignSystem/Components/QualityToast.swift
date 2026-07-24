import SwiftUI

/// 撮影品質判定の結果トースト（03 §2.4 / SCREEN_CAMERA §2）。
/// ✓=accent / ✕=danger、記号併記（色覚対応）。
public struct QualityToast: View {
    public struct Line: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let passed: Bool
        public let text: String

        public init(passed: Bool, text: String) {
            self.passed = passed
            self.text = text
        }
    }

    private let lines: [Line]
    private let suggestion: String?

    public init(lines: [Line], suggestion: String?) {
        self.lines = lines
        self.suggestion = suggestion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CIToken.Space.s) {
            // トースト文言は2行まで想定、超過はスクロール（SCR-CAMERA §13）
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: CIToken.Space.xs) {
                    ForEach(lines) { line in
                        HStack(spacing: CIToken.Space.xs) {
                            Text(line.passed ? "✓" : "✕")
                                .bold()
                                .foregroundStyle(line.passed ? CIToken.Colors.accent : CIToken.Colors.danger)
                            Text(line.text)
                                .font(CIToken.Fonts.body)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(maxHeight: 88)
            .scrollBounceBehavior(.basedOnSize)

            if let suggestion {
                Text(suggestion)
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(CIToken.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ciGlass(in: RoundedRectangle(cornerRadius: CIToken.Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}
