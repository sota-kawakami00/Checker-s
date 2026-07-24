import Foundation
import Testing
import Core
@testable import AppraisalKit

/// 価格整合の検証（08_TEST_PLAN §2.1: UT-BR01/BR-02系）
@Suite("AppraisalResultValidator")
struct AppraisalResultValidatorTests {

    private func makeResult(
        appraisedPrice: Int,
        basePrice: Int,
        adjustments: [Adjustment],
        confidence: Double = 0.9
    ) -> AppraisalResult {
        AppraisalResult(
            appraisedPrice: appraisedPrice,
            tradeInReference: appraisedPrice + 80_000,
            basePrice: basePrice,
            adjustments: adjustments,
            marketAveragePrice: basePrice,
            confidence: confidence,
            repairFinding: RepairFinding(probability: 0.1, evidences: []),
            completeness: Completeness(score: 0.9, uncheckedItems: [])
        )
    }

    private let standardAdjustments = [
        Adjustment(code: "popularColor", label: "人気カラー", amount: 50_000, rationale: "人気色", evidencePhotoIds: ["p1"]),
        Adjustment(code: "nonSmoking", label: "禁煙車", amount: 30_000, rationale: "禁煙", evidencePhotoIds: []),
        Adjustment(code: "panelRepair", label: "板金跡", amount: -40_000, rationale: "板金", evidencePhotoIds: ["p2"]),
        Adjustment(code: "tireWear", label: "タイヤ摩耗", amount: -20_000, rationale: "摩耗", evidencePhotoIds: []),
        Adjustment(code: "marketDecline", label: "相場下落", amount: -10_000, rationale: "下落", evidencePhotoIds: [])
    ]

    @Test("UT-BR02-01: base 1,800,000 + (+50k+30k-40k-20k-10k) = 1,810,000 は検証OK")
    func br02Valid() throws {
        let result = makeResult(appraisedPrice: 1_810_000, basePrice: 1_800_000, adjustments: standardAdjustments)
        let validated = try AppraisalResultValidator.validate(result, validPhotoIds: ["p1", "p2"], marketAverage: 1_800_000)
        #expect(validated.needsReview == false)
    }

    @Test("UT-BR02-02: 内訳合計と価格が1円でも不一致なら aiInvalidResponse")
    func br02Mismatch() {
        let result = makeResult(appraisedPrice: 1_810_000, basePrice: 1_800_001, adjustments: standardAdjustments)
        #expect(throws: AppError.self) {
            try AppraisalResultValidator.validate(result, validPhotoIds: ["p1", "p2"], marketAverage: nil)
        }
    }

    @Test("UT-BR01-01: 1,813,000円（万未満端数）は丸め検証NG")
    func br01NotRounded() {
        let adjustments = [Adjustment(code: "x", label: "調整", amount: 13_000, rationale: "-", evidencePhotoIds: [])]
        let result = makeResult(appraisedPrice: 1_813_000, basePrice: 1_800_000, adjustments: adjustments)
        do {
            _ = try AppraisalResultValidator.validate(result, validPhotoIds: [], marketAverage: nil)
            Issue.record("BR-01違反が検出されなかった")
        } catch let error as AppError {
            guard case .aiInvalidResponse(let reason) = error else {
                Issue.record("想定外のエラー: \(error)")
                return
            }
            #expect(reason.contains("BR-01"))
        } catch {
            Issue.record("想定外のエラー型: \(error)")
        }
    }

    @Test("UT-BR02-03: adjustments空 + base==price は検証OK")
    func br02EmptyAdjustments() throws {
        let result = makeResult(appraisedPrice: 1_800_000, basePrice: 1_800_000, adjustments: [])
        _ = try AppraisalResultValidator.validate(result, validPhotoIds: [], marketAverage: 1_800_000)
    }

    @Test("UT-BR02-04: evidencePhotoId が存在しないIDを参照したら aiInvalidResponse")
    func br02UnknownEvidence() {
        let result = makeResult(appraisedPrice: 1_810_000, basePrice: 1_800_000, adjustments: standardAdjustments)
        do {
            _ = try AppraisalResultValidator.validate(result, validPhotoIds: ["p1"], marketAverage: nil)  // p2 が不在
            Issue.record("evidence不整合が検出されなかった")
        } catch let error as AppError {
            guard case .aiInvalidResponse = error else {
                Issue.record("想定外のエラー: \(error)")
                return
            }
        } catch {
            Issue.record("想定外のエラー型: \(error)")
        }
    }

    @Test("相場平均の0.3〜1.7倍の外は needsReview 付与（05 §3.3-4）")
    func needsReviewOutOfRange() throws {
        let result = makeResult(appraisedPrice: 1_800_000, basePrice: 1_800_000, adjustments: [])
        let validated = try AppraisalResultValidator.validate(result, validPhotoIds: [], marketAverage: 1_000_000)  // 1.8倍
        #expect(validated.needsReview == true)

        let inRange = try AppraisalResultValidator.validate(result, validPhotoIds: [], marketAverage: 1_500_000)  // 1.2倍
        #expect(inRange.needsReview == false)
    }

    @Test("examples/appraisal_result.example.json がデコード・検証を通過する（Schema is Law）")
    func exampleDecodesAndValidates() throws {
        let data = try Fixtures.data("appraisal_result.example")
        let result = try AppraisalResult.decode(from: data)
        #expect(result.appraisedPrice == 1_820_000)
        #expect(result.basePrice == 1_810_000)
        #expect(result.adjustments.count == 5)
        #expect(result.confidence == 0.94)
        #expect(result.repairFinding.evidences.count == 1)
        #expect(result.completeness.uncheckedItems.map(\.code) == ["spareKey", "maintenanceBook", "underbody"])

        let photoIds: Set<String> = ["ph_front_001", "ph_intf_009", "ph_intr_010", "ph_left_003", "ph_dmg_013", "ph_fl_005"]
        let validated = try AppraisalResultValidator.validate(result, validPhotoIds: photoIds, marketAverage: result.marketAveragePrice)
        #expect(validated.needsReview == false)

        // 再エンコード→再デコードで同一（監査用原本 aiResultJSON の往復）
        let roundTripped = try AppraisalResult.decode(from: validated.encoded())
        #expect(roundTripped == validated)
    }
}
