import Foundation
import CoreGraphics
import Testing
import Core
import CameraKit
import AppraisalKit
@testable import CarInspectorAI

/// 撮影フロー（SCREEN_CAMERA §14: SCR-CAM系）
@MainActor
@Suite("CameraViewModel", .serialized)
struct CameraViewModelTests {

    struct StubDetector: VehicleDetecting {
        var bbox: PhotoQualityResult.Metrics.BBox
        func detectVehicle(in image: CGImage) async -> PhotoQualityResult.Metrics.BBox? { bbox }
    }

    struct StubMaskDetector: SensitiveRegionDetecting {
        func detectRegions(in image: CGImage) async throws -> [MaskRegion] { [] }
    }

    static let centeredBBox = PhotoQualityResult.Metrics.BBox(x: 0.1, y: 0.15, w: 0.8, h: 0.7)
    static let clippedBBox = PhotoQualityResult.Metrics.BBox(x: 0.0, y: 0.1, w: 0.9, h: 0.8)

    private func makeEnvironment(
        detectorBBox: PhotoQualityResult.Metrics.BBox = CameraViewModelTests.centeredBBox,
        frame: @escaping @Sendable (Int) -> CGImage = { SyntheticImage.sharpCar(seed: UInt64($0 + 1)) }
    ) async throws -> (AppContainer, CameraViewModel, String) {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let vehicle = Vehicle(makerCode: "toyota", modelCode: "voxy", modelYear: 2021, mileageKm: 42_000, colorCode: "pearlWhite")
        let appraisal = try await container.appraisalService.createDraft(vehicle: vehicle)

        let photoService = PhotoServiceImpl(
            context: container.modelContainer.mainContext,
            vehicleDetector: StubDetector(bbox: detectorBBox),
            maskingPipeline: MaskingPipeline(detector: StubMaskDetector()),
            tiltProvider: FixedTiltProvider(tilt: 1.0)
        )
        let session = MockCameraSession(frameProvider: frame)
        let viewModel = CameraViewModel(
            appraisalId: appraisal.id,
            photoService: photoService,
            appraisalService: container.appraisalService,
            session: session,
            tiltProvider: FixedTiltProvider(tilt: 1.0)
        )
        await viewModel.onAppear()
        return (container, viewModel, appraisal.id)
    }

    @Test("SCR-CAM-01: 12枚合格でダメージ撮影セクションへ自動遷移")
    func twelveShotsCompleteFlow() async throws {
        let (_, viewModel, _) = try await makeEnvironment()
        #expect(viewModel.phase == .ready)
        #expect(viewModel.currentAngle == .front)

        for index in 0..<12 {
            await viewModel.capture()
            #expect(viewModel.capturedPhotos.count == index + 1, "撮影\(index + 1)枚目")
        }
        #expect(viewModel.phase == .damageCapture)
        #expect(viewModel.guidedProgress == "12/12")
        #expect(viewModel.canSubmit)
    }

    @Test("SCR-CAM-02: 中断→再開で撮影済みが復元され続きから再開")
    func restoreAfterInterruption() async throws {
        let (container, viewModel, appraisalId) = try await makeEnvironment()
        for _ in 0..<3 {
            await viewModel.capture()
        }
        #expect(viewModel.capturedPhotos.count == 3)

        // 新しい ViewModel（アプリ再起動相当）
        let photoService = PhotoServiceImpl(
            context: container.modelContainer.mainContext,
            vehicleDetector: StubDetector(bbox: Self.centeredBBox),
            maskingPipeline: MaskingPipeline(detector: StubMaskDetector()),
            tiltProvider: FixedTiltProvider(tilt: 1.0)
        )
        let restored = CameraViewModel(
            appraisalId: appraisalId,
            photoService: photoService,
            appraisalService: container.appraisalService,
            session: MockCameraSession(),
            tiltProvider: FixedTiltProvider(tilt: 1.0)
        )
        await restored.onAppear()

        #expect(restored.capturedPhotos.count == 3)
        #expect(restored.currentAngle == PhotoAngle.guided[3])  // 4枚目から再開
    }

    @Test("SCR-CAM-03: framing NG で「このまま使う」→ qualityPassed=false 記録で次へ")
    func acceptFramingNG() async throws {
        let (container, viewModel, appraisalId) = try await makeEnvironment(detectorBBox: Self.clippedBBox)

        await viewModel.capture()
        #expect(viewModel.qualityToast?.passed == false)
        #expect(viewModel.canAcceptDespiteWarning)   // framing は非blocking
        #expect(viewModel.capturedPhotos.isEmpty)

        await viewModel.acceptDespiteWarning()
        #expect(viewModel.capturedPhotos.count == 1)
        #expect(viewModel.currentAngle == PhotoAngle.guided[1])

        let appraisal = try await container.appraisalService.appraisal(id: appraisalId)
        #expect(appraisal.photos.first?.qualityPassed == false)
    }

    @Test("SCR-CAM-04: focus NG では「このまま使う」が出ない（blocking）")
    func blurredCannotAccept() async throws {
        let (_, viewModel, _) = try await makeEnvironment(frame: { _ in SyntheticImage.blurred() })

        await viewModel.capture()
        #expect(viewModel.qualityToast?.passed == false)
        #expect(viewModel.qualityToast?.hasBlockingIssue == true)
        #expect(!viewModel.canAcceptDespiteWarning)
        #expect(viewModel.capturedPhotos.isEmpty)

        viewModel.retake()
        #expect(viewModel.qualityToast == nil)
    }

    @Test("UI-01相当: 送信で AI査定キューに入り、写真はマスク済のみアップロード対象になる")
    func submitEnqueues() async throws {
        let (container, viewModel, appraisalId) = try await makeEnvironment()
        for _ in 0..<12 {
            await viewModel.capture()
        }
        viewModel.skipDamageCapture()
        let submitted = await viewModel.submitForAppraisal()
        #expect(submitted)

        let appraisal = try await container.appraisalService.appraisal(id: appraisalId)
        #expect(appraisal.status == .aiRunning || appraisal.status == .aiCompleted)
        // 全写真にマスク済ファイルが存在（07 §2.2）
        for photo in appraisal.photos {
            let maskedPath = try #require(photo.localMaskedPath)
            #expect(FileManager.default.fileExists(atPath: maskedPath))
        }
    }
}
