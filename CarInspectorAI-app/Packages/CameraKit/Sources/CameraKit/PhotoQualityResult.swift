import Foundation
import Core

/// 写真品質判定の統一結果（schemas/photo_quality.schema.json 準拠）。
/// 端末内一次判定・クラウド二次判定の双方が本形式で出力する。
public struct PhotoQualityResult: Codable, Equatable, Sendable {
    public var photoId: String
    public var source: Source
    public var passed: Bool
    public var issues: [Issue]
    public var metrics: Metrics?

    public enum Source: String, Codable, Sendable {
        case onDevice, cloud
    }

    public struct Issue: Codable, Equatable, Sendable, Identifiable {
        public var code: Code
        public var message: String
        public var suggestion: String
        /// true=再撮影必須（focus/brightness）。false=許容可（framing等 SCR-CAMERA §2）
        public var blocking: Bool

        public var id: String { code.rawValue }

        public enum Code: String, Codable, Sendable {
            case focus, brightness, framing, tilt
            case angleMatch, reflection, obstruction, coverage, unjudgeable
        }

        public init(code: Code, message: String, suggestion: String, blocking: Bool) {
            self.code = code
            self.message = message
            self.suggestion = suggestion
            self.blocking = blocking
        }
    }

    public struct Metrics: Codable, Equatable, Sendable {
        public var laplacianVariance: Double?
        public var brightnessMedian: Double?
        public var tiltDegrees: Double?
        public var vehicleBBox: BBox?

        public struct BBox: Codable, Equatable, Sendable {
            public var x: Double
            public var y: Double
            public var w: Double
            public var h: Double

            public init(x: Double, y: Double, w: Double, h: Double) {
                self.x = x
                self.y = y
                self.w = w
                self.h = h
            }
        }

        public init(laplacianVariance: Double?, brightnessMedian: Double?, tiltDegrees: Double?, vehicleBBox: BBox?) {
            self.laplacianVariance = laplacianVariance
            self.brightnessMedian = brightnessMedian
            self.tiltDegrees = tiltDegrees
            self.vehicleBBox = vehicleBBox
        }
    }

    public init(photoId: String, source: Source, passed: Bool, issues: [Issue], metrics: Metrics?) {
        self.photoId = photoId
        self.source = source
        self.passed = passed
        self.issues = issues
        self.metrics = metrics
    }

    /// 再撮影必須か（focus/brightness NG。SCR-CAMERA §2:「このまま使う」は非blockingのみ）
    public var hasBlockingIssue: Bool {
        issues.contains(where: \.blocking)
    }
}
