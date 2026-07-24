import SwiftUI

/// 空状態イラスト+CTA（03 §2.4/§4）
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let ctaTitle: String?
    private let action: (() -> Void)?

    public init(systemImage: String, title: String, message: String, ctaTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.ctaTitle = ctaTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: CIToken.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(CIToken.Colors.primary.opacity(0.6))
            Text(title)
                .font(CIToken.Fonts.titleL)
            Text(message)
                .font(CIToken.Fonts.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let ctaTitle, let action {
                PrimaryButton(ctaTitle, action: action)
                    .frame(maxWidth: 280)
            }
        }
        .padding(CIToken.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// オフライン時の常設バナー（03 §2.4 / SCREEN_HOME §2-⑥）
public struct OfflineBanner: View {
    private let queuedCount: Int

    public init(queuedCount: Int) {
        self.queuedCount = queuedCount
    }

    public var body: some View {
        HStack(spacing: CIToken.Space.s) {
            Image(systemName: "wifi.slash")
            if queuedCount > 0 {
                Text(L10n.format("offline.banner.queued %lld", queuedCount))
            } else {
                Text(L10n.string("offline.banner"))
            }
            Spacer()
        }
        .font(CIToken.Fonts.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, CIToken.Space.m)
        .padding(.vertical, CIToken.Space.s)
        .background(CIToken.Colors.warning)
        .accessibilityElement(children: .combine)
    }
}

/// スケルトン行（03 §4: loading はスケルトン表示。スピナー単体は禁止）
public struct SkeletonCard: View {
    @State private var pulse = false

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: CIToken.Radius.card, style: .continuous)
            .fill(Color.gray.opacity(pulse ? 0.12 : 0.22))
            .frame(height: 88)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}
