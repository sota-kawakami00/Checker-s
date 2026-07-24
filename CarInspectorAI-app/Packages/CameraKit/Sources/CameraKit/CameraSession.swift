import Foundation
import CoreGraphics
import Core

/// 撮影フレーム
public struct CapturedFrame: Sendable {
    public var image: CGImage
    public var takenAt: Date

    public init(image: CGImage, takenAt: Date = .now) {
        self.image = image
        self.takenAt = takenAt
    }
}

/// カメラセッションの抽象（AVFoundation実機 / モック静止画。SCREEN_CAMERA §15-4）
@MainActor
public protocol CameraSessionProviding: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var isTorchOn: Bool { get }
    func requestAccess() async -> Bool
    func start() async
    func stop()
    func capturePhoto() async throws -> CapturedFrame
    func toggleTorch()
    func switchCamera()
}

/// シミュレータ・Preview 用モックセッション（静止画供給）。
/// `AppContainer.mock()` / カメラ非搭載環境のフォールバックとして使用。
@MainActor
public final class MockCameraSession: CameraSessionProviding {
    public private(set) var isTorchOn = false
    public var isAvailable: Bool { true }
    /// テストで差し替え可能なフレーム供給源
    public var frameProvider: @Sendable (Int) -> CGImage
    private var captureCount = 0

    public init(frameProvider: @escaping @Sendable (Int) -> CGImage = { SyntheticImage.sharpCar(seed: UInt64($0 + 1)) }) {
        self.frameProvider = frameProvider
    }

    public func requestAccess() async -> Bool { true }
    public func start() async {}
    public func stop() {}

    public func capturePhoto() async throws -> CapturedFrame {
        captureCount += 1
        return CapturedFrame(image: frameProvider(captureCount))
    }

    public func toggleTorch() { isTorchOn.toggle() }
    public func switchCamera() {}
}

#if os(iOS)
import AVFoundation
import UIKit

/// AVFoundation 実機セッション（SCREEN_CAMERA §5）。
/// セッション管理・撮影のみを担い、品質判定・マスキングは PhotoService 側。
@MainActor
public final class AVCameraSession: NSObject, CameraSessionProviding {
    public let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .back
    private var captureContinuation: CheckedContinuation<CapturedFrame, Error>?

    public private(set) var isTorchOn = false

    public var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    public func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    public func start() async {
        guard session.inputs.isEmpty else {
            if !session.isRunning { startRunning() }
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            device = camera
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        startRunning()
    }

    private func startRunning() {
        nonisolated(unsafe) let session = self.session
        Task.detached { session.startRunning() }
    }

    public func stop() {
        nonisolated(unsafe) let session = self.session
        Task.detached { session.stopRunning() }
    }

    public func capturePhoto() async throws -> CapturedFrame {
        try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.flashMode = isTorchOn ? .on : .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    public func toggleTorch() {
        guard let device, device.hasTorch else {
            isTorchOn.toggle()
            return
        }
        try? device.lockForConfiguration()
        device.torchMode = device.torchMode == .on ? .off : .on
        isTorchOn = device.torchMode == .on
        device.unlockForConfiguration()
    }

    public func switchCamera() {
        position = position == .back ? .front : .back
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            device = camera
        }
        session.commitConfiguration()
    }
}

extension AVCameraSession: AVCapturePhotoCaptureDelegate {
    public nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        nonisolated(unsafe) let cgImage = photo.cgImageRepresentation()
        Task { @MainActor in
            if let error {
                captureContinuation?.resume(throwing: AppError.photoQualityCheckFailed)
                CILogger.logger(category: "Camera").error("capture failed: \(error.localizedDescription)")
            } else if let cgImage {
                captureContinuation?.resume(returning: CapturedFrame(image: cgImage))
            } else {
                captureContinuation?.resume(throwing: AppError.photoQualityCheckFailed)
            }
            captureContinuation = nil
        }
    }
}
#endif
