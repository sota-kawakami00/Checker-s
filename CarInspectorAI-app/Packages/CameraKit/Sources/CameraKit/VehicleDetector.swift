import Foundation
import CoreGraphics
import Core
@preconcurrency import Vision

/// 車両BBox検出（05 §2.2 見切れ判定の入力）。テストではモック注入。
public protocol VehicleDetecting: Sendable {
    func detectVehicle(in image: CGImage) async -> PhotoQualityResult.Metrics.BBox?
}

/// Vision の物体顕著性（objectness saliency）で主要被写体のBBoxを推定する実装。
/// （車両クラス専用検出器は将来 CoreML モデルに差し替え可能なよう protocol 化）
public struct SaliencyVehicleDetector: VehicleDetecting {
    public init() {}

    public func detectVehicle(in image: CGImage) async -> PhotoQualityResult.Metrics.BBox? {
        let sendableImage = image
        return await Task.detached(priority: .userInitiated) { () -> PhotoQualityResult.Metrics.BBox? in
            let request = VNGenerateObjectnessBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: sendableImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first,
                  let salient = observation.salientObjects?.max(by: {
                      $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
                  }) else {
                return nil
            }
            let box = salient.boundingBox   // 左下原点
            return PhotoQualityResult.Metrics.BBox(
                x: box.origin.x,
                y: 1 - box.origin.y - box.height,
                w: box.width,
                h: box.height
            )
        }.value
    }
}

/// 端末の水平計（SCREEN_CAMERA §5: CoreMotion）。テスト・シミュレータではモック。
@MainActor
public protocol TiltProviding: AnyObject, Sendable {
    var currentTiltDegrees: Double? { get }
    func start()
    func stop()
}

@MainActor
public final class FixedTiltProvider: TiltProviding {
    public var currentTiltDegrees: Double?

    public init(tilt: Double? = 0) {
        currentTiltDegrees = tilt
    }

    public func start() {}
    public func stop() {}
}

#if os(iOS)
import CoreMotion

/// CoreMotion による実機水平計
@MainActor
public final class MotionTiltProvider: TiltProviding {
    private let manager = CMMotionManager()
    public private(set) var currentTiltDegrees: Double?

    public init() {}

    public func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            // 端末ロール角（横持ち撮影時の水平からのずれ）
            self?.currentTiltDegrees = motion.attitude.roll * 180 / .pi
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
#endif
