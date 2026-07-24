import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
import Core
@testable import CameraKit

/// マスキング（08_TEST_PLAN §2.4: UT-MASK系）
@Suite("MaskingPipeline")
struct MaskingPipelineTests {

    struct FixedDetector: SensitiveRegionDetecting {
        var regions: [MaskRegion]
        func detectRegions(in image: CGImage) async throws -> [MaskRegion] { regions }
    }

    struct FailingDetector: SensitiveRegionDetecting {
        func detectRegions(in image: CGImage) async throws -> [MaskRegion] {
            throw AppError.photoQualityCheckFailed
        }
    }

    /// 指定領域のグレースケール分散（ぼかし確認用）
    private func regionVariance(_ image: CGImage, rect: CGRect) -> Double {
        let gray = QualityAnalyzer.grayImage(from: image, maxEdge: max(image.width, image.height))
        var values: [Double] = []
        let x0 = Int(rect.origin.x * Double(gray.width))
        let y0 = Int(rect.origin.y * Double(gray.height))
        let x1 = min(gray.width, x0 + Int(rect.width * Double(gray.width)))
        let y1 = min(gray.height, y0 + Int(rect.height * Double(gray.height)))
        for y in y0..<y1 {
            for x in x0..<x1 {
                values.append(Double(gray.pixels[y * gray.width + x]))
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
    }

    @Test("UT-MASK-01: 検出領域（ナンバー相当）がぼかされ判読不能になる")
    func maskedRegionIsBlurred() async {
        let source = SyntheticImage.sharpCar()
        let plateRect = CGRect(x: 0.35, y: 0.55, width: 0.3, height: 0.12)
        let pipeline = MaskingPipeline(detector: FixedDetector(regions: [
            MaskRegion(kind: .licensePlate, rect: plateRect)
        ]))

        let masked = await pipeline.process(source)
        #expect(masked.maskVerified)
        #expect(masked.maskedRegionCount == 1)

        // ぼかし後は領域内の高周波成分（分散）が大きく低下する
        let maskedImage = decode(masked.jpegData)
        let before = regionVariance(source, rect: plateRect)
        let after = regionVariance(maskedImage, rect: plateRect)
        #expect(after < before * 0.35, "masked variance \(after) should be far below original \(before)")
    }

    @Test("UT-MASK-02: EXIF GPS付き画像 → 出力にEXIF/GPSなし")
    func exifGPSRemoved() async throws {
        // GPS/EXIF付きJPEGを作成
        let source = SyntheticImage.sharpCar()
        let withGPS = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(withGPS, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.6812,
                kCGImagePropertyGPSLongitude: 139.7671
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "TestLens 4.2mm"
            ]
        ]
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        CGImageDestinationFinalize(destination)

        let sourceRef = try #require(CGImageSourceCreateWithData(withGPS as CFData, nil))
        let originalProperties = try #require(CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any])
        #expect(originalProperties[kCGImagePropertyGPSDictionary] != nil)  // 前提: GPSが入っている

        let inputImage = try #require(CGImageSourceCreateImageAtIndex(sourceRef, 0, nil))
        let pipeline = MaskingPipeline(detector: FixedDetector(regions: []))
        let masked = await pipeline.process(inputImage)

        let outRef = try #require(CGImageSourceCreateWithData(masked.jpegData as CFData, nil))
        let outProperties = try #require(CGImageSourceCopyPropertiesAtIndex(outRef, 0, nil) as? [CFString: Any])
        #expect(outProperties[kCGImagePropertyGPSDictionary] == nil)
        let exif = outProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] == nil)
    }

    @Test("UT-MASK-03: 検出失敗画像は maskVerified=false（手動マスク導線）だがアップロード自体は継続可能")
    func detectorFailureFallsBack() async {
        let pipeline = MaskingPipeline(detector: FailingDetector())
        let masked = await pipeline.process(SyntheticImage.sharpCar())
        #expect(!masked.maskVerified)
        #expect(!masked.jpegData.isEmpty)  // 業務停止回避（07 §2.2）
    }

    @Test("FR-306: 長辺2048px超は縮小され、JPEGで出力される")
    func resizeAndEncode() async {
        let big = SyntheticImage.sharpCar(width: 4000, height: 3000)
        let pipeline = MaskingPipeline(detector: FixedDetector(regions: []))
        let masked = await pipeline.process(big)
        let image = decode(masked.jpegData)
        #expect(max(image.width, image.height) <= Int(CameraKitConstants.uploadLongEdge))
        #expect(masked.jpegData.prefix(2) == Data([0xFF, 0xD8]))  // JPEG SOI
    }

    private func decode(_ data: Data) -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            preconditionFailure("decode failed")
        }
        return image
    }
}
