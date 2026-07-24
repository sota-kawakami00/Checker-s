import Foundation
import Testing
import SwiftData
import Core
import AppraisalKit
@testable import SyncKit

/// オフラインキュー（08_TEST_PLAN §2.3: UT-SYNC-01〜06）
@MainActor
@Suite("SyncQueue")
struct SyncQueueTests {

    struct Environment {
        let container: ModelContainer
        let backend: InMemoryRemoteBackend
        let connectivity: ManualConnectivity
        let sync: SyncServiceImpl
        let appraisalService: AppraisalServiceImpl
        let auth: SyncKit.MockAuthService
    }

    private func makeEnvironment(online: Bool) throws -> Environment {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let backend = InMemoryRemoteBackend(appraisalDelay: .milliseconds(30))
        let connectivity = ManualConnectivity(online: online)
        let notifier = AppraisalChangeNotifier()
        let masters = try MasterCatalog.bundled()
        let sync = SyncServiceImpl(
            container: container,
            backend: backend,
            connectivity: connectivity,
            masters: masters,
            notifier: notifier,
            backoff: [.milliseconds(1), .milliseconds(1), .milliseconds(1)],
            sleeper: { _ in }
        )
        let defaults = UserDefaults(suiteName: "sync-tests-\(UUID().uuidString)") ?? .standard
        let auth = SyncKit.MockAuthService(defaults: defaults)
        let appraisalService = AppraisalServiceImpl(
            container: container,
            auth: auth,
            sync: sync,
            masters: masters,
            notifier: notifier
        )
        return Environment(container: container, backend: backend, connectivity: connectivity, sync: sync, appraisalService: appraisalService, auth: auth)
    }

    private func makeReadyAppraisal(_ environment: Environment, photoCount: Int = 2) async throws -> Appraisal {
        _ = try await environment.auth.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let vehicle = Vehicle(
            vin: "ZWR80-1234567",
            makerCode: "toyota",
            modelCode: "voxy",
            modelYear: 2021,
            mileageKm: 42_000,
            colorCode: "pearlWhite"
        )
        let appraisal = try await environment.appraisalService.createDraft(vehicle: vehicle)

        // マスク済ファイルを実際に置く（アップロードはマスク済のみ 07 §2.2）
        let directory = FileManager.default.temporaryDirectory.appending(path: "sync-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<photoCount {
            let maskedURL = directory.appending(path: "masked-\(index).jpg")
            try Data([0xFF, 0xD8, 0xFF, 0xE0, UInt8(index)]).write(to: maskedURL)
            let photo = PhotoAsset(
                appraisalId: appraisal.id,
                angle: index == 0 ? .front : .interiorFront,
                localOriginalPath: "/dev/null",
                localMaskedPath: maskedURL.path,
                qualityPassed: true
            )
            environment.container.mainContext.insert(photo)
            appraisal.photos.append(photo)
        }
        try environment.container.mainContext.save()
        return appraisal
    }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("UT-SYNC-01: オフラインで requestAIAppraisal → SyncTask登録・pendingUpload のまま")
    func offlineEnqueue() async throws {
        let environment = try makeEnvironment(online: false)
        let appraisal = try await makeReadyAppraisal(environment)

        try await environment.appraisalService.requestAIAppraisal(appraisalId: appraisal.id)

        // キュー実行は起きない（オフライン）
        try? await Task.sleep(for: .milliseconds(100))
        let tasks = try environment.container.mainContext.fetch(FetchDescriptor<SyncTask>())
        #expect(tasks.count == 4)   // doc + photo×2 + AI
        #expect(tasks.allSatisfy { $0.state == .pendingUpload })
        #expect(environment.backend.uploadedAppraisals.isEmpty)
        #expect(environment.sync.currentQueueStatus.pendingCount == 4)
        #expect(!environment.sync.currentQueueStatus.isOnline)
    }

    @Test("UT-SYNC-02: 復帰イベントで自動同期が始まり createdAt 昇順で実行される")
    func autoSyncOnReconnect() async throws {
        let environment = try makeEnvironment(online: false)
        let appraisal = try await makeReadyAppraisal(environment)
        try await environment.appraisalService.requestAIAppraisal(appraisalId: appraisal.id)

        environment.connectivity.set(online: true)   // 復帰

        await waitUntil { environment.sync.currentQueueStatus.totalQueued == 0 }
        #expect(environment.backend.uploadedAppraisals[appraisal.id] != nil)
        #expect(environment.backend.uploadedPhotos.count == 2)
        #expect(environment.backend.appraisalRequests.count == 1)

        // AI結果がリスナー経由で反映される（UC-02の後半）
        await waitUntil { appraisal.status == .aiCompleted }
        #expect(appraisal.status == .aiCompleted)
        #expect(appraisal.aiProposedPrice != nil)
        #expect(appraisal.aiConfidence != nil)
    }

    @Test("UT-SYNC-03: 同一appraisalIdのタスクは投入順に直列実行される")
    func serialExecutionPerAppraisal() async throws {
        let environment = try makeEnvironment(online: true)
        let appraisal = try await makeReadyAppraisal(environment)

        try await environment.appraisalService.requestAIAppraisal(appraisalId: appraisal.id)
        await waitUntil { environment.sync.currentQueueStatus.totalQueued == 0 }

        // ドキュメント → 写真 → AIリクエストの順（05 §1 / SCREEN_CAMERA §6）
        #expect(environment.backend.appraisalRequests.count == 1)
        let request = try #require(environment.backend.appraisalRequests.first)
        // AIリクエスト時点で写真は全て Storage 済（＝直列順序が守られた）
        #expect(request.photos.allSatisfy { environment.backend.uploadedPhotos[$0.storagePath] != nil })
    }

    @Test("UT-SYNC-04: 3回連続失敗で failed になり FR-702 のUIに露出する")
    func failsAfterThreeRetries() async throws {
        let environment = try makeEnvironment(online: true)
        let appraisal = try await makeReadyAppraisal(environment, photoCount: 0)
        environment.backend.uploadFailuresRemaining = 99

        environment.sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        try await environment.sync.syncNow()

        await waitUntil { environment.sync.currentQueueStatus.failedCount == 1 }
        let tasks = try environment.container.mainContext.fetch(FetchDescriptor<SyncTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.state == .failed)
        #expect(tasks.first?.retryCount == SyncServiceImpl.maxRetries)
        #expect(appraisal.syncState == .failed)

        // FR-702: 手動再送で回復
        environment.backend.uploadFailuresRemaining = 0
        try await environment.sync.retryFailed()
        await waitUntil { environment.sync.currentQueueStatus.totalQueued == 0 }
        #expect(environment.backend.uploadedAppraisals[appraisal.id] != nil)
    }

    @Test("UT-SYNC-05: 画像アップ未完で runAppraisal は前提条件スキップ→画像完了後に自動実行")
    func aiRequestWaitsForPhotoUpload() async throws {
        let environment = try makeEnvironment(online: true)
        let appraisal = try await makeReadyAppraisal(environment)

        // AIリクエストだけ先にキュー投入（写真アップロードタスクなし）
        appraisal.syncState = .synced
        environment.sync.enqueue(kind: .requestAIAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        try await environment.sync.syncNow()

        // 前提未達 → 実行されず pending のまま（failedにもならない）
        #expect(environment.backend.appraisalRequests.isEmpty)
        let tasks = try environment.container.mainContext.fetch(FetchDescriptor<SyncTask>())
        #expect(tasks.first?.state == .pendingUpload)
        #expect(tasks.first?.retryCount == 0)

        // 写真アップロード完了後に自動実行される
        for photo in appraisal.photos {
            environment.sync.enqueue(kind: .uploadPhoto, targetId: photo.id, appraisalId: appraisal.id)
        }
        try await environment.sync.syncNow()
        await waitUntil { !environment.backend.appraisalRequests.isEmpty }
        #expect(environment.backend.appraisalRequests.count == 1)
    }

    @Test("UT-SYNC-06: サーバー競合はサーバー版採用 + ローカル退避コピー生成")
    func conflictResolution() async throws {
        let environment = try makeEnvironment(online: true)
        let appraisal = try await makeReadyAppraisal(environment, photoCount: 0)
        appraisal.confirmedPrice = 1_500_000
        appraisal.adjustmentReason = "ローカルの調整"
        try environment.container.mainContext.save()

        var serverDTO = AppraisalMapper.dto(from: appraisal)
        serverDTO.confirmedPrice = 1_650_000
        serverDTO.adjustmentReason = "サーバー側の調整"
        serverDTO.status = AppraisalStatus.confirmed.rawValue
        environment.backend.conflictOnNextUpload = serverDTO

        environment.sync.enqueue(kind: .uploadAppraisal, targetId: appraisal.id, appraisalId: appraisal.id)
        try await environment.sync.syncNow()
        await waitUntil { environment.sync.currentQueueStatus.totalQueued == 0 }

        // サーバー版採用
        #expect(appraisal.confirmedPrice == 1_650_000)
        #expect(appraisal.adjustmentReason == "サーバー側の調整")
        #expect(appraisal.status == .confirmed)
        #expect(appraisal.syncState == .synced)

        // ローカル退避コピー
        let all = try environment.container.mainContext.fetch(FetchDescriptor<Appraisal>())
        let escape = all.first { $0.syncState == .conflict }
        #expect(escape != nil)
        #expect(escape?.confirmedPrice == 1_500_000)
        #expect(escape?.adjustmentReason == "ローカルの調整")
    }

    @Test("冪等性: 同一リクエストIDのAI依頼は1回だけ実行される（06 §2.1）")
    func idempotentAIRequest() async throws {
        let environment = try makeEnvironment(online: true)
        let appraisal = try await makeReadyAppraisal(environment)
        try await environment.appraisalService.requestAIAppraisal(appraisalId: appraisal.id)
        await waitUntil { environment.sync.currentQueueStatus.totalQueued == 0 }
        await waitUntil { appraisal.status == .aiCompleted }

        // 修復歴あり→再査定（BR-04）は新しい requestId で実行される
        try await environment.appraisalService.setRepairConfirmed(appraisalId: appraisal.id, state: .confirmedYes)
        await waitUntil { environment.backend.appraisalRequests.count == 2 }
        #expect(environment.backend.appraisalRequests.count == 2)
        let first = environment.backend.appraisalRequests[0]
        let second = environment.backend.appraisalRequests[1]
        #expect(first.requestId != second.requestId)
        #expect(second.repairConfirmed == true)

        // 再査定完了で修復歴減点が反映される
        await waitUntil { appraisal.status == .aiCompleted }
        let result = try #require(appraisal.aiResultJSON.flatMap { try? AppraisalResult.decode(from: $0) })
        #expect(result.adjustments.contains { $0.code == "repairHistory" })
        #expect(result.appraisedPrice == result.basePrice + result.adjustments.reduce(0) { $0 + $1.amount })
    }

    @Test("AI失敗イベントで aiFailureReason が立ち、再試行導線になる（05 §3.4）")
    func aiFailureSurfaced() async throws {
        let environment = try makeEnvironment(online: true)
        let appraisal = try await makeReadyAppraisal(environment)
        environment.backend.failNextAppraisalReason = "quota"

        try await environment.appraisalService.requestAIAppraisal(appraisalId: appraisal.id)
        await waitUntil { appraisal.aiFailureReason != nil }
        #expect(appraisal.aiFailureReason == "quota")
        #expect(appraisal.status == .aiRunning)   // Running画面が failed 表示に切り替わる
    }
}
