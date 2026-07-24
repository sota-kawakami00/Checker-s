import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// デザイントークン（03_UI_UX_GUIDELINE.md §2）。直値使用禁止（CLAUDE.md §2.3）。
public enum CIToken {

    // MARK: - §2.1 カラー

    public enum Colors {
        /// 主要アクション
        public static let primary = dynamic(light: 0x0A84FF, dark: 0x409CFF)
        /// 成功・加点
        public static let accent = dynamic(light: 0x30D158, dark: 0x30DB5B)
        /// 要確認・注意
        public static let warning = dynamic(light: 0xFF9F0A, dark: 0xFFB340)
        /// 減点・修復歴警告
        public static let danger = dynamic(light: 0xFF453A, dark: 0xFF6961)
        /// 査定価格数値
        public static let priceText = dynamic(light: 0x1C1C1E, dark: 0xFFFFFF)
        /// 画面背景
        public static var bgBase: Color {
            #if canImport(UIKit)
            Color(UIColor.systemGroupedBackground)
            #else
            Color(NSColor.windowBackgroundColor)
            #endif
        }

        static func dynamic(light: UInt32, dark: UInt32) -> Color {
            #if canImport(UIKit)
            Color(UIColor { trait in
                UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
            })
            #else
            Color(rgb: light)
            #endif
        }
    }

    /// ガラスマテリアル（§2.1 ci.glass / ci.glassStrong）
    public enum Materials {
        /// ガラスカード
        public static let glass: Material = .ultraThinMaterial
        /// 価格など重要情報の背面（可読性最優先）
        public static let glassStrong: Material = .thickMaterial
    }

    // MARK: - §2.3 スペーシング・形状

    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    public enum Radius {
        public static let card: CGFloat = 20
        public static let button: CGFloat = 14
    }

    public enum Shadow {
        public static let cardY: CGFloat = 2
        public static let cardBlur: CGFloat = 12
        public static let cardOpacity: Double = 0.08
    }

    // MARK: - §2.2 タイポグラフィ（全て Dynamic Type 対応）

    public enum Fonts {
        /// 画面見出し
        public static let titleL: Font = .title2.bold()
        /// 本文
        public static let body: Font = .body
        /// 補足・根拠説明
        public static let caption: Font = .caption
        /// 金額・走行距離等の数値（桁ブレ防止 monospacedDigit 必須）
        public static let mono: Font = .body.monospacedDigit()
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// 金額表示ユーティリティ（¥1,830,000 形式 + VoiceOver用読み上げ「百八十三万円」）
public enum PriceFormatting {
    private static let grouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    private static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    public static func yen(_ amount: Int) -> String {
        "¥\(grouping.string(from: NSNumber(value: amount)) ?? String(amount))"
    }

    /// 符号付き（加減点表示用、色だけに依存しない NFR-10）
    public static func signedYen(_ amount: Int) -> String {
        amount >= 0 ? "+\(yen(amount))" : "−\(yen(abs(amount)))"
    }

    /// VoiceOver: 「百八十三万円」形式（数値の分解読み禁止、03 §5）
    public static func spokenYen(_ amount: Int) -> String {
        "\(spellOut.string(from: NSNumber(value: amount)) ?? String(amount))円"
    }
}
