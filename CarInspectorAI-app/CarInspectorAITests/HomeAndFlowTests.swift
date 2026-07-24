import Foundation
import CoreGraphics
import Testing
import Core
import AppraisalKit
import CameraKit
import SyncKit
@testable import CarInspectorAI

/// ホーム表示 + UC-01/02 の結合フロー（SCREEN_HOME §14 / 08 §4 UI-01/02 のロジック層検証）
@MainActor
@Suite("HomeAndFlow", .serialized)
struct HomeAndFlowTests {

    @Test("SCR-HOME-03: 初回起動は empty 状態")
    func firstLaunchEmpty() async throws {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let viewModel = HomeViewModel(
            appraisalService: container.appraisalService,
            syncService: container.syncService,
            auth: container.authService,
            storeName: container.store.name
        )
        await viewModel.onAppear()
        #expect(viewModel.phase == .empty)
        #expect(viewModel.staffName == "佐藤 花子")
    }

    @Test("SCR-HOME-01: 下書き2件+解析中1件が進行中カードに出る")
    func inProgressCards() async throws {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let context = container.modelContainer.mainContext

        for status in [AppraisalStatus.draft, .draft, .aiRunning, .confirmed] {
            let appraisal = Appraisal(
                storeId: "store-demo",
                staffId: "staff-demo",
                status: status,
                vehicle: Vehicle(makerCode: "toyota", modelCode: "voxy", mileageKm: 1000, colorCode: "black")
            )
            if status == .confirmed {
                appraisal.confirmedPrice = 1_000_000
                appraisal.expiresAt = Date(timeIntervalSinceNow: 6 * 86_400)
            }
            context.insert(appraisal)
        }
        try context.save()

        let viewModel = HomeViewModel(
            appraisalService: container.appraisalService,
            syncService: container.syncService,
            auth: container.authService,
            storeName: container.store.name
        )
        await viewModel.onAppear()

        #expect(viewModel.phase == .content)
        #expect(viewModel.inProgress.count == 3)
        #expect(viewModel.recentConfirmed.count == 1)
        #expect(viewModel.todayCount == 4)
    }

    @Test("要確認判定: aiCompleted + 低confidence/修復歴疑いで needsAttention")
    func needsAttention() async throws {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let viewModel = HomeViewModel(
            appraisalService: container.appraisalService,
            syncService: container.syncService,
            auth: container.authService,
            storeName: container.store.name
        )
        let vehicle = Vehicle(makerCode: "toyota", modelCode: "voxy", mileageKm: 1000, colorCode: "black")
        let appraisal = Appraisal(storeId: "s", staffId: "s", status: .aiCompleted, vehicle: vehicle)

        appraisal.aiConfidence = 0.94
        appraisal.repairProbability = 0.1
        #expect(!viewModel.needsAttention(appraisal))

        appraisal.aiConfidence = 0.7   // < 0.8 → 要確認バッジ（FR-404）
        #expect(viewModel.needsAttention(appraisal))

        appraisal.aiConfidence = 0.94
        appraisal.repairProbability = 0.6   // 修復歴疑い
        #expect(viewModel.needsAttention(appraisal))
    }

    @Test("UC-01ロジック完走: 下書き→撮影12枚→AI査定→確定→PDF")
    func uc01EndToEnd() async throws {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")

        // 車両情報（M2）
        let vehicleVM = VehicleInfoViewModel(
            vehicleService: container.vehicleService,
            appraisalService: container.appraisalService,
            draftId: nil
        )
        await vehicleVM.onAppear()
        vehicleVM.makerCode = "toyota"
        vehicleVM.modelCode = "voxy"
        vehicleVM.modelYear = 2021
        vehicleVM.mileageText = "42000"
        vehicleVM.colorCode = "pearlWhite"
        let appraisalId = try #require(await vehicleVM.proceedToCamera())

        // 撮影（M3）
        struct CenterDetector: VehicleDetecting {
            func detectVehicle(in image: CGImage) async -> PhotoQualityResult.Metrics.BBox? {
                .init(x: 0.1, y: 0.15, w: 0.8, h: 0.7)
            }
        }
        struct NoMask: SensitiveRegionDetecting {
            func detectRegions(in image: CGImage) async throws -> [MaskRegion] { [] }
        }
        let photoService = PhotoServiceImpl(
            context: container.modelContainer.mainContext,
            vehicleDetector: CenterDetector(),
            maskingPipeline: MaskingPipeline(detector: NoMask()),
            tiltProvider: FixedTiltProvider(tilt: 1.0)
        )
        let cameraVM = CameraViewModel(
            appraisalId: appraisalId,
            photoService: photoService,
            appraisalService: container.appraisalService,
            session: MockCameraSession(),
            tiltProvider: FixedTiltProvider(tilt: 1.0)
        )
        await cameraVM.onAppear()
        for _ in 0..<12 {
            await cameraVM.capture()
        }
        cameraVM.skipDamageCapture()
        #expect(await cameraVM.submitForAppraisal())

        // AI査定（M4、モックCF）→ 結果受信（M5）
        let resultVM = AppraisalResultViewModel(
            appraisalService: container.appraisalService,
            pdfService: container.pdfService,
            auth: container.authService,
            masters: container.masters
        )
        await resultVM.observe(appraisalId: appraisalId)

        let deadline = ContinuousClock.now + .seconds(15)
        while resultVM.phase != .reviewing && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(resultVM.phase == .reviewing)
        let result = try #require(resultVM.result)
        // BR-02（クライアント検証済みの結果のみ表示される）
        #expect(result.basePrice + result.adjustments.reduce(0) { $0 + $1.amount } == result.appraisedPrice)
        #expect(result.appraisedPrice % 10_000 == 0)   // BR-01
        // 12枚撮影 → 高confidence（情報充足）
        #expect(result.confidence >= 0.8)

        // 確定 → PDF（M7）
        await resultVM.confirm()
        #expect(resultVM.appraisal?.status == .confirmed)
        let pdfURL = try #require(await resultVM.generatePDF())
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))
    }

    @Test("UC-02ロジック: 機内モードで査定実行→キュー退避→復帰で自動実行・結果反映")
    func uc02OfflineFlow() async throws {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let manual = try #require(container.connectivity as? ManualConnectivity)
        let context = container.modelContainer.mainContext

        // 撮影完了済みの査定を用意（マスク済ファイルあり）
        let vehicle = Vehicle(makerCode: "toyota", modelCode: "voxy", modelYear: 2021, mileageKm: 42_000, colorCode: "pearlWhite")
        let appraisal = try await container.appraisalService.createDraft(vehicle: vehicle)
        let directory = FileManager.default.temporaryDirectory.appending(path: "uc02-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let maskedURL = directory.appending(path: "front.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: maskedURL)
        let photo = PhotoAsset(appraisalId: appraisal.id, angle: .front, localOriginalPath: "/dev/null", localMaskedPath: maskedURL.path, qualityPassed: true)
        context.insert(photo)
        appraisal.photos.append(photo)
        try context.save()

        // 機内モードで実行 → キュー退避（UC-02）
        manual.set(online: false)
        try await container.appraisalService.requestAIAppraisal(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(200))
        #expect(appraisal.status == .aiRunning)
        #expect(appraisal.aiResultJSON == nil)
        #expect(container.syncService.currentQueueStatus.pendingCount > 0)
        #expect(!container.syncService.currentQueueStatus.isOnline)

        // 復帰 → 自動同期 → AI完了（NFR-05 / モックCFは1.5s遅延）
        manual.set(online: true)
        let deadline = ContinuousClock.now + .seconds(15)
        while appraisal.status != .aiCompleted && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(appraisal.status == .aiCompleted)
        #expect(appraisal.aiProposedPrice != nil)
        #expect(container.syncService.currentQueueStatus.totalQueued == 0)
    }
}
