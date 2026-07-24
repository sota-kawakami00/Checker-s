import Foundation
import CoreGraphics
import SwiftData
import Core

/// 撮影された1枚（マスキング前。端末外へは出さない）
public struct CapturedPhoto: Sendable {
    public var id: String
    public var image: CGImage
    public var tiltDegrees: Double?
    public var takenAt: Date

    public init(id: String = UUID().uuidString, image: CGImage, tiltDegrees: Double? = nil, takenAt: Date = .now) {
        self.id = id
        self.image = image
        self.tiltDegrees = tiltDegrees
        self.takenAt = takenAt
    }
}

/// マスキング済み写真（原本JPEG + アップロード用マスク済JPEG）
public struct MaskedPhoto: Sendable {
    public var capturedId: String
    public var originalJPEG: Data
    public var masked: MaskedImage
    public var takenAt: Date

    public init(capturedId: String, originalJPEG: Data, masked: MaskedImage, takenAt: Date) {
        self.capturedId = capturedId
        self.originalJPEG = originalJPEG
        self.masked = masked
        self.takenAt = takenAt
    }
}

/// 撮影・品質判定・マスキング・保存（06 §1.3）
@MainActor
public protocol PhotoService: AnyObject, Sendable {
    func capture(session: any CameraSessionProviding) async throws -> CapturedPhoto
    /// 端末内一次判定（05 §2 / NFR-01: 1.5秒SLA。超過時は判定スキップで撮影を止めない）
    func checkQuality(_ photo: CapturedPhoto, angle: PhotoAngle) async throws -> PhotoQualityResult
    /// ナンバー/顔マスキング + EXIF除去 + リサイズ圧縮（FR-305/306, 07 §2.2）
    func mask(_ photo: CapturedPhoto) async throws -> MaskedPhoto
    /// PhotoAsset を SwiftData に保存（アップロード対象はマスク済のみ）
    func persist(
        _ photo: MaskedPhoto,
        appraisalId: String,
        angle: PhotoAngle,
        damageTag: String?,
        memo: String?,
        quality: PhotoQualityResult?
    ) async throws -> PhotoAsset
}

@MainActor
public final class PhotoServiceImpl: PhotoService {
    private let context: ModelContext
    private let analyzer = QualityAnalyzer()
    private let vehicleDetector: any VehicleDetecting
    private let maskingPipeline: MaskingPipeline
    private let tiltProvider: any TiltProviding
    private let logger = CILogger.logger(category: "PhotoService")

    public init(
        context: ModelContext,
        vehicleDetector: any VehicleDetecting = SaliencyVehicleDetector(),
        maskingPipeline: MaskingPipeline = MaskingPipeline(),
        tiltProvider: any TiltProviding
    ) {
        self.context = context
        self.vehicleDetector = vehicleDetector
        self.maskingPipeline = maskingPipeline
        self.tiltProvider = tiltProvider
    }

    public func capture(session: any CameraSessionProviding) async throws -> CapturedPhoto {
        let frame = try await session.capturePhoto()
        return CapturedPhoto(image: frame.image, tiltDegrees: tiltProvider.currentTiltDegrees, takenAt: frame.takenAt)
    }

    public func checkQuality(_ photo: CapturedPhoto, angle: PhotoAngle) async throws -> PhotoQualityResult {
        let started = ContinuousClock.now
        let sla = CameraKitConstants.qualityCheckSLA
        let analyzer = self.analyzer
        let detector = self.vehicleDetector
        let image = photo.image
        let photoId = photo.id
        let tilt = photo.tiltDegrees

        let work = Task.detached(priority: .userInitiated) { () -> PhotoQualityResult in
            let gray = QualityAnalyzer.grayImage(from: image)
            let bbox = await detector.detectVehicle(in: image)
            return analyzer.analyze(.init(photoId: photoId, angle: angle, image: gray, vehicleBBox: bbox, tiltDegrees: tilt))
        }

        // NFR-01: 1.5s以内。超過時は判定スキップ+警告バッジ付きで続行（SCREEN_CAMERA §10）
        let timeout = Task.detached {
            try await Task.sleep(for: .seconds(sla))
        }
        let result: PhotoQualityResult
        do {
            result = try await withThrowingTaskGroup(of: PhotoQualityResult?.self) { group in
                group.addTask { await work.value }
                group.addTask {
                    try? await timeout.value
                    return nil
                }
                defer { group.cancelAll() }
                for try await first in group {
                    if let first { return first }
                    // タイムアウト側が先に完了
                    work.cancel()
                    return PhotoQualityResult(
                        photoId: photoId,
                        source: .onDevice,
                        passed: true,
                        issues: [.init(
                            code: .unjudgeable,
                            message: L10n.string("quality.timeout.message"),
                            suggestion: L10n.string("quality.timeout.suggestion"),
                            blocking: false
                        )],
                        metrics: nil
                    )
                }
                throw AppError.photoQualityCheckFailed
            }
        } catch {
            throw AppError.photoQualityCheckFailed
        }

        let elapsed = started.duration(to: .now)
        logger.info("quality check (signpost相当) elapsed=\(elapsed.components.seconds).\(elapsed.components.attoseconds / 1_000_000_000_000_000)s photo=\(photoId, privacy: .public)")
        return result
    }

    public func mask(_ photo: CapturedPhoto) async throws -> MaskedPhoto {
        guard let originalJPEG = MaskingPipeline.encodeJPEGStrippingMetadata(photo.image, quality: 0.92) else {
            throw AppError.photoQualityCheckFailed
        }
        let masked = await maskingPipeline.process(photo.image)
        return MaskedPhoto(capturedId: photo.id, originalJPEG: originalJPEG, masked: masked, takenAt: photo.takenAt)
    }

    public func persist(
        _ photo: MaskedPhoto,
        appraisalId: String,
        angle: PhotoAngle,
        damageTag: String?,
        memo: String?,
        quality: PhotoQualityResult?
    ) async throws -> PhotoAsset {
        let store = try PhotoFileStore()
        let originalPath = try store.writeOriginal(photo.originalJPEG, id: photo.capturedId)
        let maskedPath = try store.writeMasked(photo.masked.jpegData, id: photo.capturedId)

        let qualityJSON = quality.flatMap { try? JSONEncoder().encode($0) }
        let asset = PhotoAsset(
            id: photo.capturedId,
            appraisalId: appraisalId,
            angle: angle,
            damageTag: damageTag,
            memo: memo,
            localOriginalPath: originalPath,
            localMaskedPath: maskedPath,
            qualityResultJSON: qualityJSON,
            qualityPassed: quality?.passed ?? false,
            maskVerified: photo.masked.maskVerified,
            uploadState: .pending,
            takenAt: photo.takenAt
        )
        context.insert(asset)

        // Appraisal.photos へ関連付け（下書き自動保存 FR-205 / 中断復帰 SCR-CAM-02）
        var descriptor = FetchDescriptor<Appraisal>(predicate: #Predicate { $0.id == appraisalId })
        descriptor.fetchLimit = 1
        if let appraisal = try context.fetch(descriptor).first {
            appraisal.photos.append(asset)
            appraisal.updatedAt = .now
        }
        try context.save()
        return asset
    }
}

/// 写真ファイルの保存先（SCREEN_CAMERA §7: Application Support/photos/、Data Protection 有効）
public struct PhotoFileStore: Sendable {
    public let originalDirectory: URL
    public let maskedDirectory: URL

    public init(base: URL? = nil) throws {
        let root = base ?? URL.applicationSupportDirectory
        originalDirectory = root.appending(path: "photos/original", directoryHint: .isDirectory)
        maskedDirectory = root.appending(path: "photos/masked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: maskedDirectory, withIntermediateDirectories: true)
    }

    public func writeOriginal(_ data: Data, id: String) throws -> String {
        let url = originalDirectory.appending(path: "\(id).jpg")
        try write(data, to: url)
        return url.path
    }

    public func writeMasked(_ data: Data, id: String) throws -> String {
        let url = maskedDirectory.appending(path: "\(id).jpg")
        try write(data, to: url)
        return url.path
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        // 端末紛失対策: iOS Data Protection（07 §1）
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}
