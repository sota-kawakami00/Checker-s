import SwiftUI

/// Liquid Glass 対応（03_UI_UX_GUIDELINE「Liquid Glass デザインシステム」）。
/// iOS 26+ / macOS 26+ ではシステムの Liquid Glass（`glassEffect`）を使用し、
/// それ以前のOSでは従来マテリアル（ultraThin/thick）へフォールバックする。
extension View {

    /// ガラス背景（ci.glass 相当）。
    /// - Parameters:
    ///   - strong: 価格など重要情報の背面は true（ci.glassStrong 相当）。
    ///     Liquid Glass 環境でも可読性最優先（03 §1-3）のため、ガラスの上に
    ///     不透明度の高いレイヤを敷いてコントラスト 4.5:1 を確保する。
    ///   - shape: ガラスの形状
    ///   - interactive: タッチ応答するガラス（操作要素向け、iOS 26+のみ効果）
    @ViewBuilder
    public func ciGlass(
        strong: Bool = false,
        in shape: some Shape,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background {
                    if strong {
                        // 数値・価格の背面には不透明度の高いレイヤ（03 §2.1 ci.glassStrong）
                        shape.fill(CIToken.Colors.bgBase.opacity(0.72))
                    }
                }
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(
                strong ? CIToken.Materials.glassStrong : CIToken.Materials.glass,
                in: shape
            )
        }
    }

    /// 画面上下のバー等、矩形領域のガラス背景
    @ViewBuilder
    public func ciGlassBar() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect)
        } else {
            self.background(CIToken.Materials.glass)
        }
    }
}

/// 複数のガラス要素をまとめ、近接時の融合（morphing）を有効にするコンテナ。
/// iOS 26 未満では単なる透過コンテナとして振る舞う。
public struct CIGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = CIToken.Space.m, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
