import SwiftUI
import Core

/// AI信頼度バッジ（03 §2.4: >=80 accent, 60-79 warning, <60 danger）
public struct ConfidenceBadge: View {
    private let confidence: Double  // 0-1

    public init(confidence: Double) {
        self.confidence = confidence
    }

    private var percent: Int { Int((confidence * 100).rounded()) }

    private var color: Color {
        switch percent {
        case 80...: CIToken.Colors.accent
        case 60..<80: CIToken.Colors.warning
        default: CIToken.Colors.danger
        }
    }

    public var body: some View {
        Label {
            Text(L10n.format("badge.confidence %lld", percent))
                .font(CIToken.Fonts.mono)
        } icon: {
            Image(systemName: percent >= 80 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
        }
        .font(CIToken.Fonts.caption)
        .padding(.horizontal, CIToken.Space.s)
        .padding(.vertical, CIToken.Space.xs)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
        .accessibilityLabel(Text(L10n.format("badge.confidence.a11y %lld", percent)))
    }
}

/// 査定ステータスChip（03 §2.4 / FR-504）
public struct StatusChip: View {
    private let status: AppraisalStatus

    public init(status: AppraisalStatus) {
        self.status = status
    }

    private var color: Color {
        switch status {
        case .draft: Color.gray
        case .aiRunning: CIToken.Colors.primary
        case .aiCompleted: CIToken.Colors.warning
        case .confirmed: CIToken.Colors.accent
        case .won: CIToken.Colors.accent
        case .lost: Color.gray
        case .expired: CIToken.Colors.danger
        }
    }

    public var body: some View {
        Text(L10n.string("status.\(status.rawValue)"))
            .font(CIToken.Fonts.caption.bold())
            .padding(.horizontal, CIToken.Space.s)
            .padding(.vertical, CIToken.Space.xs)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
