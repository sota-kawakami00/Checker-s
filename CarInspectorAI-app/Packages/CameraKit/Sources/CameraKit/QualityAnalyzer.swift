import Foundation
import CoreGraphics
import Core

/// 端末内一次品質判定（05 §2.2 / FR-302/303）。
/// 純粋な画素計算のためユニットテスト可能（UT-PQ系）。
public struct QualityAnalyzer: Sendable {

    public init() {}

    /// グレースケール画素の抽出結果
    public struct GrayImage: Sendable {
        public let pixels: [UInt8]
        public let width: Int
        public let height: Int
    }

    /// 判定入力（BBox は車両検出結果、tilt は CoreMotion 由来）
    public struct Input: Sendable {
        public var photoId: String
        public var angle: PhotoAngle
        public var image: GrayImage
        public var vehicleBBox: PhotoQualityResult.Metrics.BBox?
        public var tiltDegrees: Double?

        public init(photoId: String, angle: PhotoAngle, image: GrayImage, vehicleBBox: PhotoQualityResult.Metrics.BBox?, tiltDegrees: Double?) {
            self.photoId = photoId
            self.angle = angle
            self.image = image
            self.vehicleBBox = vehicleBBox
            self.tiltDegrees = tiltDegrees
        }
    }

    // MARK: - 判定本体

    public func analyze(_ input: Input) -> PhotoQualityResult {
        let variance = Self.laplacianVariance(input.image)
        let median = Self.brightnessMedian(input.image)
        var issues: [PhotoQualityResult.Issue] = []

        // ピント（blocking: 再撮影必須）
        if variance < CameraKitConstants.laplacianVarianceFloor {
            issues.append(.init(
                code: .focus,
                message: localized("quality.focus.message"),
                suggestion: localized("quality.focus.suggestion"),
                blocking: true
            ))
        }

        // 明るさ（blocking: 再撮影必須）
        if !CameraKitConstants.brightnessMedianRange.contains(median) {
            let dark = median < CameraKitConstants.brightnessMedianRange.lowerBound
            issues.append(.init(
                code: .brightness,
                message: localized(dark ? "quality.brightness.dark.message" : "quality.brightness.bright.message"),
                suggestion: localized(dark ? "quality.brightness.dark.suggestion" : "quality.brightness.bright.suggestion"),
                blocking: true
            ))
        }

        // 見切れ（framing、非blocking: 「このまま使う」許容）
        if input.angle != .damage, input.angle != .meter, let bbox = input.vehicleBBox {
            if Self.isClipped(bbox) {
                issues.append(.init(
                    code: .framing,
                    message: localized("quality.framing.clipped.message"),
                    suggestion: localized("quality.framing.clipped.suggestion"),
                    blocking: false
                ))
            } else if bbox.w * bbox.h < CameraKitConstants.minVehicleAreaRatio {
                issues.append(.init(
                    code: .framing,
                    message: localized("quality.framing.small.message"),
                    suggestion: localized("quality.framing.small.suggestion"),
                    blocking: false
                ))
            }
        }

        // 傾き（非blocking）
        if let tilt = input.tiltDegrees, abs(tilt) > CameraKitConstants.tiltToleranceDegrees {
            issues.append(.init(
                code: .tilt,
                message: localized("quality.tilt.message"),
                suggestion: localized("quality.tilt.suggestion"),
                blocking: false
            ))
        }

        return PhotoQualityResult(
            photoId: input.photoId,
            source: .onDevice,
            passed: issues.isEmpty,
            issues: issues,
            metrics: .init(
                laplacianVariance: variance,
                brightnessMedian: median,
                tiltDegrees: input.tiltDegrees,
                vehicleBBox: input.vehicleBBox
            )
        )
    }

    // MARK: - 画素計算（pure）

    /// ピント判定: ラプラシアン(4近傍)応答の分散
    public static func laplacianVariance(_ image: GrayImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return 0 }
        var sum = 0.0
        var sumSquares = 0.0
        var count = 0.0
        image.pixels.withUnsafeBufferPointer { pixels in
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    let center = 4 * Int(pixels[index])
                    let neighbors = Int(pixels[index - 1]) + Int(pixels[index + 1])
                        + Int(pixels[index - width]) + Int(pixels[index + width])
                    let response = Double(center - neighbors)
                    sum += response
                    sumSquares += response * response
                    count += 1
                }
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }

    /// 明るさ判定: 輝度中央値（ヒストグラム）
    public static func brightnessMedian(_ image: GrayImage) -> Double {
        guard !image.pixels.isEmpty else { return 0 }
        var histogram = [Int](repeating: 0, count: 256)
        for pixel in image.pixels {
            histogram[Int(pixel)] += 1
        }
        let half = image.pixels.count / 2
        var cumulative = 0
        for value in 0..<256 {
            cumulative += histogram[value]
            if cumulative >= half {
                return Double(value)
            }
        }
        return 255
    }

    /// 見切れ判定: BBoxが画像端に接している
    public static func isClipped(_ bbox: PhotoQualityResult.Metrics.BBox) -> Bool {
        let margin = CameraKitConstants.framingEdgeMargin
        return bbox.x <= margin
            || bbox.y <= margin
            || bbox.x + bbox.w >= 1 - margin
            || bbox.y + bbox.h >= 1 - margin
    }

    /// CGImage → グレースケール画素（8bit）
    public static func grayImage(from cgImage: CGImage, maxEdge: Int = 512) -> GrayImage {
        let scale = min(1, Double(maxEdge) / Double(max(cgImage.width, cgImage.height)))
        let width = max(1, Int(Double(cgImage.width) * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return GrayImage(pixels: pixels, width: width, height: height)
    }

    // MARK: - 文言

    private func localized(_ key: String) -> String {
        L10n.string(key)
    }
}
