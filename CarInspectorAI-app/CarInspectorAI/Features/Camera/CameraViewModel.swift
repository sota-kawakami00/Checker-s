import Foundation
import Observation
import Core
import CameraKit
import AppraisalKit

enum CameraPhase: Equatable {
    case requestingPermission
    case permissionDenied
    case ready
    case capturing
    case checkingQuality
    case damageCapture      // 12枚完了後
    case readyToSubmit
}

/// 撮影画面（SCREEN_CAMERA.md §4）。
/// 責務はフロー制御・状態保持のみ。画像処理・セッション操作は PhotoService / CameraKit へ委譲。
@MainActor
@Observable
final class CameraViewModel {

    // 状態（§4）
    private(set) var phase: CameraPhase = .requestingPermission
    private(set) var currentAngle: PhotoAngle = .front
    private(set) var capturedPhotos: [PhotoAngle: PhotoAsset] = [:]
    private(set) var damagePhotos: [PhotoAsset] = []
    private(set) var qualityToast: PhotoQualityResult?
    var levelAngle: Double = 0
    private(set) var isTorchOn = false
    var error: AppError?
    var isDamageTagSheetPresented = false
    private(set) var isSubmitting = false

    let appraisalId: String

    // 依存（protocol注入）
    private let photoService: any PhotoService
    private let appraisalService: any AppraisalService
    private let session: any CameraSessionProviding
    private let tiltProvider: any TiltProviding

    /// framing NG 等（非blocking）で「このまま使う」待ちの撮影
    private var pendingCapture: (masked: MaskedPhoto, quality: PhotoQualityResult)?
    /// ダメージ撮影でタグ付け待ちの1枚
    private var pendingDamage: (masked: MaskedPhoto, quality: PhotoQualityResult?)?

    init(
        appraisalId: String,
        photoService: any PhotoService,
        appraisalService: any AppraisalService,
        session: any CameraSessionProviding,
        tiltProvider: any TiltProviding
    ) {
        self.appraisalId = appraisalId
        self.photoService = photoService
        self.appraisalService = appraisalService
        self.session = session
        self.tiltProvider = tiltProvider
    }

    var totalCount: Int { capturedPhotos.count + damagePhotos.count }
    var guidedProgress: String { "\(capturedPhotos.count)/\(PhotoAngle.guided.count)" }
    var isLevelWarning: Bool { abs(levelAngle) > CameraKitConstants.tiltToleranceDegrees }

    // MARK: - ライフサイクル

    func onAppear() async {
        // 権限（§3: requestingPermission → ready / permissionDenied）
        guard await session.requestAccess() else {
            phase = .permissionDenied
            error = .cameraPermissionDenied
            return
        }
        await session.start()
        tiltProvider.start()
        await restore()
        advanceToNextAngle()
    }

    func onDisappear() {
        tiltProvider.stop()
        session.stop()
    }

    /// 中断復帰: 撮影済アングルを復元（SCR-CAM-02 / FR-205）
    private func restore() async {
        guard let appraisal = try? await appraisalService.appraisal(id: appraisalId) else { return }
        for photo in appraisal.photos {
            if photo.angle == .damage {
                if !damagePhotos.contains(where: { $0.id == photo.id }) {
                    damagePhotos.append(photo)
                }
            } else {
                capturedPhotos[photo.angle] = photo
            }
        }
    }

    // MARK: - 撮影（§4: capture → checkQuality（並行でmask）→ persist → 次アングル）

    func capture() async {
        guard phase == .ready || phase == .damageCapture || phase == .readyToSubmit else { return }
        let isDamage = phase == .damageCapture || phase == .readyToSubmit
        let previousPhase = phase
        phase = .capturing
        qualityToast = nil
        do {
            let raw = try await photoService.capture(session: session)
            let captured = CapturedPhoto(
                id: raw.id,
                image: raw.image,
                tiltDegrees: tiltProvider.currentTiltDegrees,
                takenAt: raw.takenAt
            )
            phase = .checkingQuality

            // マスキングは品質判定と並行で開始（§4）
            async let maskedTask = photoService.mask(captured)
            let quality = try await photoService.checkQuality(captured, angle: isDamage ? .damage : currentAngle)
            let masked = try await maskedTask

            if isDamage {
                // ダメージ自由撮影 → 部位タグシートへ（§2）
                pendingDamage = (masked, quality)
                isDamageTagSheetPresented = true
                phase = previousPhase
                return
            }

            if quality.passed {
                let asset = try await photoService.persist(
                    masked, appraisalId: appraisalId, angle: currentAngle,
                    damageTag: nil, memo: nil, quality: quality
                )
                capturedPhotos[currentAngle] = asset
                qualityToast = quality
                phase = .ready
                // OK トーストは1.2s後自動消滅（03 §3）
                let photoId = quality.photoId
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1.2))
                    if self?.qualityToast?.photoId == photoId {
                        self?.qualityToast = nil
                    }
                }
                advanceToNextAngle()
            } else {
                // NG: blocking（focus/brightness）は再撮影のみ。非blockingは「このまま使う」可（§2）
                if !quality.hasBlockingIssue {
                    pendingCapture = (masked, quality)
                }
                qualityToast = quality
                phase = .ready
            }
        } catch {
            self.error = (error as? AppError) ?? .photoQualityCheckFailed
            phase = previousPhase == .capturing ? .ready : previousPhase
        }
    }

    func retake() {
        pendingCapture = nil
        qualityToast = nil
    }

    /// framing NG のみ許容（SCR-CAM-03: qualityPassed=false を記録して次へ）
    func acceptDespiteWarning() async {
        guard let pending = pendingCapture, !pending.quality.hasBlockingIssue else { return }
        pendingCapture = nil
        qualityToast = nil
        do {
            let asset = try await photoService.persist(
                pending.masked, appraisalId: appraisalId, angle: currentAngle,
                damageTag: nil, memo: nil, quality: pending.quality
            )
            capturedPhotos[currentAngle] = asset
            advanceToNextAngle()
        } catch {
            self.error = (error as? AppError) ?? .storageFull
        }
    }

    func jumpTo(angle: PhotoAngle) {
        guard angle != .damage else { return }
        currentAngle = angle
        if phase == .damageCapture || phase == .readyToSubmit {
            phase = .ready
        }
        qualityToast = nil
        pendingCapture = nil
    }

    private func advanceToNextAngle() {
        if let next = PhotoAngle.guided.first(where: { capturedPhotos[$0] == nil }) {
            currentAngle = next
            if phase == .requestingPermission { phase = .ready }
        } else {
            // 12枚完了 → ダメージ撮影セクション（SCR-CAM-01）
            phase = damagePhotos.isEmpty ? .damageCapture : .readyToSubmit
        }
    }

    // MARK: - ダメージ撮影（FR-304）

    func addDamagePhoto() async {
        await capture()
    }

    func setDamageTag(_ tag: String, memo: String?) async {
        guard let pending = pendingDamage else { return }
        pendingDamage = nil
        isDamageTagSheetPresented = false
        do {
            let asset = try await photoService.persist(
                pending.masked, appraisalId: appraisalId, angle: .damage,
                damageTag: tag, memo: memo, quality: pending.quality
            )
            damagePhotos.append(asset)
            phase = .readyToSubmit
        } catch {
            self.error = (error as? AppError) ?? .storageFull
        }
    }

    func cancelDamageTag() {
        pendingDamage = nil
        isDamageTagSheetPresented = false
    }

    func skipDamageCapture() {
        guard phase == .damageCapture else { return }
        phase = .readyToSubmit
    }

    // MARK: - 送信（§6 / UC-02）

    var canSubmit: Bool {
        capturedPhotos.count == PhotoAngle.guided.count && !isSubmitting
    }

    /// AI査定実行 → SyncKit が (1)ドキュメント (2)画像 (3)runAppraisal を順に実行
    func submitForAppraisal() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appraisalService.requestAIAppraisal(appraisalId: appraisalId)
            return true
        } catch {
            self.error = (error as? AppError) ?? .serverError(code: 0)
            return false
        }
    }

    // MARK: - その他操作

    func toggleTorch() {
        session.toggleTorch()
        isTorchOn = session.isTorchOn
    }

    func switchCamera() {
        session.switchCamera()
    }

    func refreshLevel() {
        levelAngle = tiltProvider.currentTiltDegrees ?? 0
    }

    /// トースト表示用の行データ（DesignSystem.QualityToast へマップ）
    var toastLines: [(passed: Bool, text: String)] {
        guard let toast = qualityToast else { return [] }
        if toast.passed {
            return [(true, String(localized: "camera.quality.ok"))]
        }
        var lines: [(Bool, String)] = []
        let failedCodes = Set(toast.issues.map(\.code))
        if !failedCodes.contains(.focus) { lines.append((true, String(localized: "camera.quality.focusOK"))) }
        if !failedCodes.contains(.brightness) { lines.append((true, String(localized: "camera.quality.brightnessOK"))) }
        for issue in toast.issues {
            lines.append((false, issue.message))
        }
        return lines
    }

    var canAcceptDespiteWarning: Bool {
        pendingCapture != nil && !(qualityToast?.hasBlockingIssue ?? true) && qualityToast?.passed == false
    }
}
