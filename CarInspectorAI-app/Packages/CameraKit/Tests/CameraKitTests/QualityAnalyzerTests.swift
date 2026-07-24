import Foundation
import CoreGraphics
import Testing
import Core
@testable import CameraKit

/// 写真品質判定（08_TEST_PLAN §2.4: UT-PQ系）
@Suite("QualityAnalyzer")
struct QualityAnalyzerTests {

    private let analyzer = QualityAnalyzer()

    private func gray(_ image: CGImage) -> QualityAnalyzer.GrayImage {
        QualityAnalyzer.grayImage(from: image)
    }

    private let centeredBBox = PhotoQualityResult.Metrics.BBox(x: 0.1, y: 0.15, w: 0.8, h: 0.7)

    @Test("UT-PQ-01: ブレ画像フィクスチャは focus NG + 指定メッセージ + blocking")
    func blurredImageFailsFocus() {
        let result = analyzer.analyze(.init(
            photoId: "p1",
            angle: .front,
            image: gray(SyntheticImage.blurred()),
            vehicleBBox: centeredBBox,
            tiltDegrees: 0
        ))
        #expect(!result.passed)
        let focus = result.issues.first { $0.code == .focus }
        #expect(focus != nil)
        #expect(focus?.blocking == true)  // SCR-CAM-04: focus NG は「このまま使う」不可
        #expect(focus?.suggestion.contains("もう一度撮影") == true)
    }

    @Test("UT-PQ-02: 低輝度フィクスチャは brightness NG")
    func darkImageFailsBrightness() {
        let result = analyzer.analyze(.init(
            photoId: "p2",
            angle: .front,
            image: gray(SyntheticImage.dark()),
            vehicleBBox: centeredBBox,
            tiltDegrees: 0
        ))
        #expect(!result.passed)
        let brightness = result.issues.first { $0.code == .brightness }
        #expect(brightness != nil)
        #expect(brightness?.blocking == true)
        #expect(brightness?.suggestion.contains("明るい場所") == true)
    }

    @Test("UT-PQ-03: 車両見切れ（front）は framing NG「下がって撮影」・非blocking")
    func clippedVehicleFailsFraming() {
        let clippedBBox = PhotoQualityResult.Metrics.BBox(x: 0.0, y: 0.1, w: 0.9, h: 0.85)  // 左端に接触
        let result = analyzer.analyze(.init(
            photoId: "p3",
            angle: .front,
            image: gray(SyntheticImage.sharpCar()),
            vehicleBBox: clippedBBox,
            tiltDegrees: 0
        ))
        #expect(!result.passed)
        let framing = result.issues.first { $0.code == .framing }
        #expect(framing != nil)
        #expect(framing?.blocking == false)  // SCR-CAM-03: framing NG は「このまま使う」可
        #expect(framing?.suggestion.contains("下がって") == true)
    }

    @Test("良品画像は全項目合格し metrics が入る")
    func sharpImagePasses() {
        let result = analyzer.analyze(.init(
            photoId: "p4",
            angle: .front,
            image: gray(SyntheticImage.sharpCar()),
            vehicleBBox: centeredBBox,
            tiltDegrees: 1.5
        ))
        #expect(result.passed)
        #expect(result.issues.isEmpty)
        #expect(result.metrics?.laplacianVariance ?? 0 >= CameraKitConstants.laplacianVarianceFloor)
        #expect(CameraKitConstants.brightnessMedianRange.contains(result.metrics?.brightnessMedian ?? -1))
    }

    @Test("傾き ±7°超は tilt NG（05 §2.2）・非blocking")
    func tiltDetection() {
        let result = analyzer.analyze(.init(
            photoId: "p5",
            angle: .front,
            image: gray(SyntheticImage.sharpCar()),
            vehicleBBox: centeredBBox,
            tiltDegrees: 9.5
        ))
        let tilt = result.issues.first { $0.code == .tilt }
        #expect(tilt != nil)
        #expect(tilt?.blocking == false)
        #expect(tilt?.suggestion.contains("水平") == true)

        let ok = analyzer.analyze(.init(
            photoId: "p6",
            angle: .front,
            image: gray(SyntheticImage.sharpCar()),
            vehicleBBox: centeredBBox,
            tiltDegrees: 6.9
        ))
        #expect(!ok.issues.contains { $0.code == .tilt })
    }

    @Test("damage/meter アングルは framing 判定をスキップ")
    func damageSkipsFraming() {
        let clippedBBox = PhotoQualityResult.Metrics.BBox(x: 0.0, y: 0.0, w: 1.0, h: 1.0)
        let result = analyzer.analyze(.init(
            photoId: "p7",
            angle: .damage,
            image: gray(SyntheticImage.sharpCar()),
            vehicleBBox: clippedBBox,
            tiltDegrees: 0
        ))
        #expect(!result.issues.contains { $0.code == .framing })
    }

    @Test("品質結果は photo_quality schema 形式でエンコードできる")
    func encodesToSchemaShape() throws {
        let result = analyzer.analyze(.init(
            photoId: "p8",
            angle: .front,
            image: gray(SyntheticImage.blurred()),
            vehicleBBox: centeredBBox,
            tiltDegrees: 0
        ))
        let data = try JSONEncoder().encode(result)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["photoId"] as? String == "p8")
        #expect(json["source"] as? String == "onDevice")
        #expect(json["passed"] as? Bool == false)
        let issues = try #require(json["issues"] as? [[String: Any]])
        for issue in issues {
            #expect(issue["code"] != nil)
            #expect(issue["message"] != nil)
            #expect(issue["suggestion"] != nil)
            #expect(issue["blocking"] != nil)
        }
    }

    @Test("NFR-01: 一次判定の計算は1.5秒以内（p95相当・粗い性能確認）")
    func performanceWithinSLA() {
        let image = gray(SyntheticImage.sharpCar(width: 1280, height: 960))
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<5 {
                _ = analyzer.analyze(.init(photoId: "perf", angle: .front, image: image, vehicleBBox: centeredBBox, tiltDegrees: 0))
            }
        }
        #expect(elapsed < .seconds(CameraKitConstants.qualityCheckSLA * 5))
    }
}
