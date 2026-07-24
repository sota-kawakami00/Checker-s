import SwiftUI

/// ガラスマテリアルの角丸カード。全画面の基本コンテナ（03 §2.4）。
public struct GlassCard<Content: View>: View {
    private let strong: Bool
    private let content: Content

    /// - Parameter strong: 価格など重要情報の背面には true（ci.glassStrong、可読性 4.5:1 確保）
    public init(strong: Bool = false, @ViewBuilder content: () -> Content) {
        self.strong = strong
        self.content = content()
    }

    public var body: some View {
        content
            .padding(CIToken.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ciGlass(strong: strong, in: RoundedRectangle(cornerRadius: CIToken.Radius.card, style: .continuous))
            .shadow(
                color: .black.opacity(CIToken.Shadow.cardOpacity),
                radius: CIToken.Shadow.cardBlur,
                x: 0,
                y: CIToken.Shadow.cardY
            )
    }
}
