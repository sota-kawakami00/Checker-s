import Foundation
import Core

/// 確定操作のガード条件（BR-01/BR-03/UC-03/FR-407）。
/// ViewModel の `canConfirm` と Service 側検証の両方がこの1箇所を使う
/// （SCREEN_APPRAISAL_RESULT.md §15-5: ガードロジックは1箇所に集約）。
public enum ConfirmBlocker: Equatable, Sendable {
    /// BR-03: AI信頼度 < 60% は staff 確定不可（manager 承認で例外可）
    case lowConfidenceNeedsManager
    /// UC-03: 修復歴疑い（probability >= 0.5）は現車確認なしで確定不可
    case repairUnconfirmed
    /// FR-407: AI提案額と異なる価格には調整理由が必須
    case adjustmentReasonRequired
    /// BR-01: 価格は1万円単位
    case priceUnitInvalid
    /// AI査定が完了していない
    case aiNotCompleted
}

public enum ConfirmGuard {
    /// 信頼度の確定下限（BR-03）
    public static let confidenceFloor = 0.6
    /// 修復歴の要確認しきい値（UC-03 / FR-405）
    public static let repairSuspectThreshold = 0.5

    public static func blockers(
        status: AppraisalStatus,
        aiConfidence: Double?,
        repairProbability: Double?,
        repairConfirmedState: RepairConfirmedState?,
        aiProposedPrice: Int?,
        requestedPrice: Int,
        adjustmentReason: String?,
        role: StaffRole
    ) -> [ConfirmBlocker] {
        var blockers: [ConfirmBlocker] = []

        if status != .aiCompleted {
            blockers.append(.aiNotCompleted)
        }

        // BR-03: confidence < 60% は manager 以上のみ確定可
        if let confidence = aiConfidence, confidence < confidenceFloor, role < .manager {
            blockers.append(.lowConfidenceNeedsManager)
        }

        // UC-03: 修復歴疑いは現車確認（あり/なし/不明のいずれか選択）まで確定不可
        if let probability = repairProbability, probability >= repairSuspectThreshold,
           (repairConfirmedState ?? RepairConfirmedState.none) == RepairConfirmedState.none {
            blockers.append(.repairUnconfirmed)
        }

        // FR-407: AI提案額と異なる確定額には理由必須
        if let proposed = aiProposedPrice, requestedPrice != proposed {
            let trimmed = (adjustmentReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                blockers.append(.adjustmentReasonRequired)
            }
        }

        // BR-01: 1万円単位
        if requestedPrice < 0 || requestedPrice % 10_000 != 0 {
            blockers.append(.priceUnitInvalid)
        }

        return blockers
    }
}
