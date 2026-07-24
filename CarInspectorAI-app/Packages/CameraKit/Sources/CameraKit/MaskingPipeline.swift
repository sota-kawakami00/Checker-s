import Foundation
import CoreGraphics
import ImageIO
import CoreImage
import UniformTypeIdentifiers
import Core
@preconcurrency import Vision

/// マスク対象領域（正規化座標。原点は左上）
public struct MaskRegion: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case licensePlate, face
    }

    public var kind: Kind
    public var rect: CGRect   // 0-1 正規化

    public init(kind: Kind, rect: CGRect) {
        self.kind = kind
        self.rect = rect
    }
}

/// ナンバープレート・顔の検出（07 §2.2）。テストではモック注入。
public protocol SensitiveRegionDetecting: Sendable {
    func detectRegions(in image: CGImage) async throws -> [MaskRegion]
}

/// Vision による検出実装:
/// - 顔: VNDetectFaceRectanglesRequest
/// - ナンバー: VNRecognizeTextRequest（プレート形状のテキスト領域）+ VNDetectRectanglesRequest の複合
public struct VisionSensitiveRegionDetector: SensitiveRegionDetecting {
    public init() {}

    public func detectRegions(in image: CGImage) async throws -> [MaskRegion] {
        let sendableImage = image
        return try await Task.detached(priority: .userInitiated) {
            var regions: [MaskRegion] = []

            let faceRequest = VNDetectFaceRectanglesRequest()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast
            textRequest.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: sendableImage, options: [:])
            try handler.perform([faceRequest, textRequest])

            for face in faceRequest.results ?? [] {
                regions.append(MaskRegion(kind: .face, rect: Self.flip(face.boundingBox)))
            }
            // ナンバープレート候補: 数字を含む横長の小さめテキスト領域
            for text in textRequest.results ?? [] {
                guard let candidate = text.topCandidates(1).first else { continue }
                let box = text.boundingBox
                let isPlateShaped = box.width / max(box.height, 0.001) > 1.5 && box.height < 0.2
                let containsDigits = candidate.string.rangeOfCharacter(from: .decimalDigits) != nil
                if isPlateShaped && containsDigits {
                    regions.append(MaskRegion(kind: .licensePlate, rect: Self.flip(box)))
                }
            }
            return regions
        }.value
    }

    /// Vision は左下原点 → 左上原点へ変換
    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x, y: 1 - rect.origin.y - rect.height, width: rect.width, height: rect.height)
    }
}

/// マスキング済み画像（アップロード可能なのはこれのみ。07 §2.2）
public struct MaskedImage: Sendable {
    public var jpegData: Data
    public var maskVerified: Bool     // 検出処理が正常完了したか
    public var maskedRegionCount: Int
}

/// マスキングパイプライン（07 §2.2）:
/// 検出 → ガウシアンぼかし(r=20相当) → EXIF/GPS除去 → リサイズ(長辺2048)・JPEG80% (FR-306)
public struct MaskingPipeline: Sendable {
    private let detector: any SensitiveRegionDetecting

    public init(detector: any SensitiveRegionDetecting = VisionSensitiveRegionDetector()) {
        self.detector = detector
    }

    public func process(_ image: CGImage) async -> MaskedImage {
        var regions: [MaskRegion] = []
        var maskVerified = true
        do {
            regions = try await detector.detectRegions(in: image)
        } catch {
            // 検出失敗のフォールバック: maskVerified=false（手動マスク導線 UT-MASK-03）。
            // アップロード不可にはしない（業務停止回避、07 §2.2）
            maskVerified = false
        }

        let masked = Self.applyBlur(to: image, regions: regions)
        let resized = Self.resize(masked, longEdge: CameraKitConstants.uploadLongEdge)
        let jpeg = Self.encodeJPEGStrippingMetadata(resized, quality: CameraKitConstants.uploadJPEGQuality)

        return MaskedImage(
            jpegData: jpeg ?? Data(),
            maskVerified: maskVerified && jpeg != nil,
            maskedRegionCount: regions.count
        )
    }

    // MARK: - 加工（pure・テスト対象）

    /// 指定領域にガウシアンぼかしを適用
    public static func applyBlur(to image: CGImage, regions: [MaskRegion]) -> CGImage {
        guard !regions.isEmpty else { return image }
        let ciImage = CIImage(cgImage: image)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var output = ciImage

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        for region in regions {
            // 正規化(左上原点) → CoreImage座標(左下原点、ピクセル)
            let rect = CGRect(
                x: region.rect.origin.x * width,
                y: (1 - region.rect.origin.y - region.rect.height) * height,
                width: region.rect.width * width,
                height: region.rect.height * height
            ).integral

            guard let blur = CIFilter(name: "CIGaussianBlur") else { continue }
            blur.setValue(output.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(CameraKitConstants.maskBlurRadius, forKey: kCIInputRadiusKey)
            guard let blurred = blur.outputImage else { continue }
            output = blurred.cropped(to: rect).composited(over: output)
        }

        return context.createCGImage(output, from: CGRect(x: 0, y: 0, width: width, height: height)) ?? image
    }

    /// 長辺 longEdge に収まるよう縮小（拡大はしない）
    public static func resize(_ image: CGImage, longEdge: CGFloat) -> CGImage {
        let currentLongEdge = CGFloat(max(image.width, image.height))
        guard currentLongEdge > longEdge else { return image }
        let scale = longEdge / currentLongEdge
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// EXIF/GPS を含む全メタデータを除去してJPEGエンコード（NFR-07 / FR-306）
    public static func encodeJPEGStrippingMetadata(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        // kCGImageDestinationMetadata を渡さないことで元画像のメタデータを引き継がない
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
