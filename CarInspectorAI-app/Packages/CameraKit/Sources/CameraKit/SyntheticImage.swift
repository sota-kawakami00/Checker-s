import Foundation
import CoreGraphics
import CoreText

/// 合成画像ジェネレータ。
/// - テストの品質フィクスチャ（UT-PQ系）
/// - シミュレータ用モックカメラのフレーム供給（SCREEN_CAMERA §15-4: 静止画モックセッション）
public enum SyntheticImage {

    /// 決定論的な乱数（テスト再現性のため seed 固定可能）
    struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        mutating func double() -> Double {
            Double(next() % 10_000) / 10_000
        }
    }

    /// シャープでテクスチャのある「車両らしい」画像（品質判定を通過する）
    public static func sharpCar(width: Int = 640, height: Int = 480, seed: UInt64 = 1) -> CGImage {
        draw(width: width, height: height) { context, random in
            // 背景（中間輝度 + 高周波ノイズ → ピント判定OK・輝度OK）
            context.setFillColor(CGColor(gray: 0.55, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var rng = random
            for _ in 0..<(width * height / 24) {
                let x = rng.double() * Double(width)
                let y = rng.double() * Double(height)
                let gray = 0.25 + rng.double() * 0.6
                context.setFillColor(CGColor(gray: gray, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
            // 車体シルエット（中央 70%）
            let body = CGRect(x: Double(width) * 0.15, y: Double(height) * 0.3, width: Double(width) * 0.7, height: Double(height) * 0.35)
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.beginPath()
            context.addPath(CGPath(roundedRect: body, cornerWidth: 24, cornerHeight: 24, transform: nil))
            context.fillPath()
            // タイヤ
            context.setFillColor(CGColor(gray: 0.05, alpha: 1))
            context.fillEllipse(in: CGRect(x: body.minX + 30, y: body.minY - 25, width: 60, height: 60))
            context.fillEllipse(in: CGRect(x: body.maxX - 90, y: body.minY - 25, width: 60, height: 60))
            // ナンバープレート位置（マスキング確認用の明部）
            context.setFillColor(CGColor(gray: 0.95, alpha: 1))
            context.fill(CGRect(x: body.midX - 45, y: body.minY + 8, width: 90, height: 26))
        }
    }

    /// ブレ画像相当（滑らかなグラデーションのみ → ラプラシアン分散が低い）
    public static func blurred(width: Int = 640, height: Int = 480) -> CGImage {
        draw(width: width, height: height) { context, _ in
            for y in 0..<height {
                let gray = 0.35 + 0.3 * Double(y) / Double(height)
                context.setFillColor(CGColor(gray: gray, alpha: 1))
                context.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
        }
    }

    /// 低輝度画像（輝度中央値 < 40）
    public static func dark(width: Int = 640, height: Int = 480, seed: UInt64 = 7) -> CGImage {
        draw(width: width, height: height) { context, random in
            context.setFillColor(CGColor(gray: 0.05, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var rng = random
            for _ in 0..<(width * height / 20) {
                let x = rng.double() * Double(width)
                let y = rng.double() * Double(height)
                context.setFillColor(CGColor(gray: rng.double() * 0.12, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
    }

    private static func draw(width: Int, height: Int, content: (CGContext, SeededRandom) -> Void) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            preconditionFailure("CGContext creation failed")
        }
        content(context, SeededRandom(seed: 1))
        guard let image = context.makeImage() else {
            preconditionFailure("makeImage failed")
        }
        return image
    }
}
