import Foundation
import Testing
import SwiftData
import Core
import AppraisalKit
import SyncKit
@testable import CarInspectorAI

/// 査定結果画面の確定ガード（SCREEN_APPRAISAL_RESULT §14: SCR-RES系）
@MainActor
@Suite("AppraisalResultViewModel")
struct AppraisalResultViewModelTests {

    private func makeEnvironment(role: StaffRole = .staff) async throws -> (AppContainer, AppraisalResultViewModel) {
        let container = AppContainer.mock()
        let email = role == .staff ? "staff@carinspector.jp" : "manager@carinspector.jp"
        _ = try await container.authService.signIn(email: email, password: "demo1234")
        let viewModel = AppraisalResultViewModel(
            appraisalService: container.appraisalService,
            pdfService: container.pdfService,
            auth: container.authService,
            masters: container.masters
        )
        return (container, viewModel)
    }

    private func insertCompleted(
        _ container: AppContainer,
        confidence: Double = 0.94,
        repairProbability: Double = 0.22
    ) throws -> Appraisal {
        let vehicle = Vehicle(makerCode: "toyota", modelCode: "voxy", modelYear: 2021, mileageKm: 42_000, colorCode: "pearlWhite")
        let appraisal = Appraisal(
            storeId: "store-demo",
            staffId: "staff-demo",
            status: .aiCompleted,
            vehicle: vehicle
        )
        appraisal.aiConfidence = confidence
        appraisal.aiProposedPrice = 1_820_000
        appraisal.repairProbability = repairProbability
        appraisal.repairConfirmedState = RepairConfirmedState.none
        let result = AppraisalResult(
            appraisedPrice: 1_820_000,
            tradeInReference: 1_900_000,
            basePrice: 1_810_000,
            adjustments: [
                Adjustment(code: "popularColor", label: "人気カラー", amount: 50_000, rationale: "-", evidencePhotoIds: []),
                Adjustment(code: "panelRepair", label: "板金跡", amount: -40_000, rationale: "-", evidencePhotoIds: [])
            ],
            marketAveragePrice: 1_810_000,
            confidence: confidence,
            repairFinding: RepairFinding(probability: repairProbability, evidences: []),
            completeness: Completeness(score: 0.9, uncheckedItems: [])
        )
        appraisal.aiResultJSON = try? result.encoded()
        container.modelContainer.mainContext.insert(appraisal)
        try container.modelContainer.mainContext.save()
        return appraisal
    }

    @Test("SCR-RES-01: aiCompleted 受信で reviewing、内訳合計=価格")
    func aiCompletedShowsReviewing() async throws {
        let (container, viewModel) = try await makeEnvironment()
        let appraisal = try insertCompleted(container)

        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.phase == .reviewing)
        let result = try #require(viewModel.result)
        let total = result.basePrice + result.adjustments.reduce(0) { $0 + $1.amount }
        #expect(total == result.appraisedPrice)
    }

    @Test("SCR-RES-02: confidence 94% は確定可")
    func highConfidenceCanConfirm() async throws {
        let (container, viewModel) = try await makeEnvironment()
        let appraisal = try insertCompleted(container, confidence: 0.94)
        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.canConfirm)
        #expect(viewModel.confirmBlockReasonKey == nil)
    }

    @Test("SCR-RES-03: confidence 59% + staff は manager 承認シートへ")
    func lowConfidenceStaffNeedsManager() async throws {
        let (container, viewModel) = try await makeEnvironment(role: .staff)
        let appraisal = try insertCompleted(container, confidence: 0.59)
        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))

        #expect(!viewModel.canConfirm)
        #expect(viewModel.confirmBlockers.contains(.lowConfidenceNeedsManager))

        await viewModel.confirm()
        #expect(viewModel.isManagerApprovalPresented)
        #expect(viewModel.appraisal?.status == .aiCompleted)  // 確定されていない

        // manager なら同条件で確定できる（BR-03例外）
        let (managerContainer, managerVM) = try await makeEnvironment(role: .manager)
        let managerAppraisal = try insertCompleted(managerContainer, confidence: 0.59)
        await managerVM.observe(appraisalId: managerAppraisal.id)
        try await Task.sleep(for: .milliseconds(100))
        await managerVM.confirm()
        #expect(managerVM.appraisal?.status == .confirmed)
    }

    @Test("SCR-RES-04: 修復歴78%・未確認は確定ボタン無効+理由提示")
    func repairSuspectedBlocksConfirm() async throws {
        let (container, viewModel) = try await makeEnvironment()
        let appraisal = try insertCompleted(container, repairProbability: 0.78)
        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))

        #expect(!viewModel.canConfirm)
        #expect(viewModel.confirmBlockers.contains(.repairUnconfirmed))
        #expect(viewModel.confirmBlockReasonKey == "result.block.repairUnconfirmed")

        // 現車確認「なし」後は確定可能（UC-03）
        await viewModel.setRepairConfirmed(.confirmedNo)
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.canConfirm)
    }

    @Test("SCR-RES-05: 修復歴「あり」選択で running へ戻り再査定される（BR-04）")
    func repairYesTriggersRerun() async throws {
        let (container, viewModel) = try await makeEnvironment()
        let appraisal = try insertCompleted(container, repairProbability: 0.78)
        // 再査定は写真アップロード完了が前提のためモック写真を用意
        let photo = PhotoAsset(appraisalId: appraisal.id, angle: .front, localOriginalPath: "/dev/null", uploadState: .done)
        container.modelContainer.mainContext.insert(photo)
        appraisal.photos.append(photo)
        appraisal.syncState = .synced
        try container.modelContainer.mainContext.save()

        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))
        await viewModel.setRepairConfirmed(.confirmedYes)
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.phase == .running)   // running へ戻る

        // モックCF完了後、修復歴減点付き価格に更新される
        try await Task.sleep(for: .seconds(2.5))
        #expect(viewModel.phase == .reviewing)
        let result = try #require(viewModel.result)
        #expect(result.adjustments.contains { $0.code == "repairHistory" })
    }

    @Test("SCR-RES-06: 調整+理由空は保存不可（FR-407）")
    func adjustmentRequiresReason() async throws {
        let (container, viewModel) = try await makeEnvironment()
        let appraisal = try insertCompleted(container)
        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))

        viewModel.adjustPrice(by: -40_000)
        #expect(viewModel.effectivePrice == 1_780_000)
        #expect(viewModel.priceDiffFromAI == -40_000)
        #expect(!viewModel.canSaveAdjustment)   // 理由空
        #expect(!viewModel.canConfirm)

        viewModel.adjustmentReason = "左前ドアの傷が想定より深いため"
        #expect(viewModel.canSaveAdjustment)
        #expect(viewModel.canConfirm)

        await viewModel.confirm()
        #expect(viewModel.appraisal?.status == .confirmed)
        #expect(viewModel.appraisal?.confirmedPrice == 1_780_000)
        #expect(viewModel.appraisal?.expiresAt != nil)  // BR-05
    }

    @Test("確定後にPDFを生成できる（FR-502）")
    func pdfAfterConfirm() async throws {
        let (container, viewModel) = try await makeEnvironment()
        let appraisal = try insertCompleted(container)
        await viewModel.observe(appraisalId: appraisal.id)
        try await Task.sleep(for: .milliseconds(100))

        // 未確定ではPDF不可
        #expect(await viewModel.generatePDF() == nil)

        await viewModel.confirm()
        let url = await viewModel.generatePDF()
        let pdfURL = try #require(url)
        let data = try Data(contentsOf: pdfURL)
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
    }
}
