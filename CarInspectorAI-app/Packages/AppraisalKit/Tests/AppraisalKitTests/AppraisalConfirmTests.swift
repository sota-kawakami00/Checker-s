import Foundation
import Testing
import SwiftData
import Core
@testable import AppraisalKit

/// 確定ガード（08_TEST_PLAN §2.2: UT-BR03 / UT-UC03 / UT-FR407）
@MainActor
@Suite("AppraisalConfirm")
struct AppraisalConfirmTests {

    @Test("UT-BR03-01: confidence 0.59 で staff が confirm すると forbidden")
    func staffCannotConfirmLowConfidence() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext, confidence: 0.59)

        await #expect(throws: AppError.forbidden) {
            try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)
        }
        #expect(appraisal.status == .aiCompleted)
    }

    @Test("UT-BR03-02: confidence 0.59 で manager が confirm すると成功し adjustmentLog が記録される")
    func managerCanConfirmLowConfidence() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .manager)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext, confidence: 0.59)

        try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)

        #expect(appraisal.status == .confirmed)
        #expect(appraisal.confirmedPrice == 1_820_000)
        #expect(appraisal.expiresAt != nil)  // BR-05: +7日

        // BR-06: 変更履歴の記録
        let logs = try container.mainContext.fetch(FetchDescriptor<AdjustmentLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.afterPrice == 1_820_000)
        #expect(logs.first?.staffId == "staff-1")

        // 確定はキューへ（オフライン確定対応 SCR-RES-07）
        #expect(sync.entries.contains { $0.kind == .uploadAppraisal && $0.appraisalId == appraisal.id })
    }

    @Test("UT-UC03-01: repairProbability 0.6・未確認のまま confirm はブロック")
    func repairUnconfirmedBlocksConfirm() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext, repairProbability: 0.6)

        await #expect(throws: AppError.validation(reason: "repairUnconfirmed")) {
            try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)
        }
    }

    @Test("UT-UC03-02: 修復歴「あり」確定で再査定リクエストが発行される（BR-04）")
    func repairConfirmedYesTriggersReappraisal() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext, repairProbability: 0.78)

        try await service.setRepairConfirmed(appraisalId: appraisal.id, state: .confirmedYes)

        #expect(appraisal.repairConfirmedState == .confirmedYes)
        #expect(appraisal.status == .aiRunning)
        #expect(sync.entries.contains { $0.kind == .requestAIAppraisal && $0.appraisalId == appraisal.id })
    }

    @Test("修復歴「なし」確認では再査定は発行されない")
    func repairConfirmedNoDoesNotTriggerReappraisal() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext, repairProbability: 0.78)

        try await service.setRepairConfirmed(appraisalId: appraisal.id, state: .confirmedNo)

        #expect(appraisal.status == .aiCompleted)
        #expect(!sync.entries.contains { $0.kind == .requestAIAppraisal })

        // 確認後は confirm 可能（UC-03）
        try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)
        #expect(appraisal.status == .confirmed)
    }

    @Test("UT-FR407-01: AI提案額と異なる額で理由なし確定はバリデーションエラー")
    func adjustmentWithoutReasonFails() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext)

        await #expect(throws: AppError.validation(reason: "adjustmentReasonRequired")) {
            try await service.confirm(appraisalId: appraisal.id, price: 1_780_000, adjustmentReason: "  ")
        }

        // 理由があれば成功
        try await service.confirm(appraisalId: appraisal.id, price: 1_780_000, adjustmentReason: "左前ドアの傷が想定より深いため")
        #expect(appraisal.confirmedPrice == 1_780_000)
    }

    @Test("BR-01: 1万円単位でない確定額はバリデーションエラー")
    func priceUnitValidation() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext)

        await #expect(throws: AppError.validation(reason: "priceUnitInvalid")) {
            try await service.confirm(appraisalId: appraisal.id, price: 1_820_500, adjustmentReason: "端数")
        }
    }

    @Test("BR-06: 確定済み価格の変更は manager のみ")
    func confirmedPriceChangeRequiresManager() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync)
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext)

        try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)
        #expect(appraisal.status == .confirmed)

        // staff による再変更は forbidden
        await #expect(throws: AppError.forbidden) {
            try await service.confirm(appraisalId: appraisal.id, price: 1_800_000, adjustmentReason: "交渉")
        }

        // manager なら変更可能 + ログが2件に
        auth.currentStaff = Staff(id: "manager-1", storeId: "store-1", displayName: "店長", email: "m@example.com", role: .manager)
        try await service.confirm(appraisalId: appraisal.id, price: 1_800_000, adjustmentReason: "顧客交渉による調整")
        #expect(appraisal.confirmedPrice == 1_800_000)
        let logs = try container.mainContext.fetch(FetchDescriptor<AdjustmentLog>())
        #expect(logs.count == 2)
    }

    @Test("BR-05: 期限切れ（確定+7日超過）は expired になる")
    func expiryDetection() async throws {
        let container = try TestFactory.makeContainer()
        let auth = MockAuthService(role: .staff)
        let sync = SpySyncEnqueuer()

        // 時計を注入し、確定時刻から8日進める
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        nonisolated(unsafe) var currentNow = base
        let service = try TestFactory.makeService(container: container, auth: auth, sync: sync, now: { currentNow })
        let appraisal = try TestFactory.makeCompletedAppraisal(context: container.mainContext)

        try await service.confirm(appraisalId: appraisal.id, price: 1_820_000, adjustmentReason: nil)
        currentNow = base.addingTimeInterval(8 * 24 * 3600)

        let reloaded = try await service.appraisal(id: appraisal.id)
        #expect(reloaded.status == .expired)
    }
}
