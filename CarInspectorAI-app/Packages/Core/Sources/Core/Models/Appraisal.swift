import Foundation
import SwiftData

/// 査定（中核エンティティ、04_DATA_MODEL.md §2.2）
@Model
public final class Appraisal {
    @Attribute(.unique) public var id: String
    public var storeId: String
    public var staffId: String
    public var status: AppraisalStatus                   // draft/aiRunning/aiCompleted/confirmed/won/lost/expired
    @Relationship(deleteRule: .cascade) public var vehicle: Vehicle
    @Relationship(deleteRule: .cascade) public var photos: [PhotoAsset]
    public var aiResultJSON: Data?                       // schemas/appraisal_result準拠の生JSON（監査用に原本保持）
    public var aiConfidence: Double?                     // 0-1
    public var aiProposedPrice: Int?                     // AI提案額（円）
    public var confirmedPrice: Int?                      // 人間確定額
    public var adjustmentReason: String?                 // 調整理由（FR-407）
    public var repairProbability: Double?
    public var repairConfirmedState: RepairConfirmedState?  // none/confirmedYes/confirmedNo/unknown
    public var completenessScore: Double?                // 査定品質 0-1
    public var uncheckedItems: [String]                  // 未確認項目コード
    public var checkedItems: [String]                    // スタッフ手動チェック済み項目コード
    public var marketAveragePrice: Int?
    public var aiFailureReason: String?                  // aiStatus=failed の理由（再試行導線用）
    public var syncState: SyncState
    public var expiresAt: Date?                          // 確定時 +7日（BR-05）
    public var deletedAt: Date?                          // 論理削除（04 §5）
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        storeId: String,
        staffId: String,
        status: AppraisalStatus = .draft,
        vehicle: Vehicle,
        photos: [PhotoAsset] = [],
        aiResultJSON: Data? = nil,
        aiConfidence: Double? = nil,
        aiProposedPrice: Int? = nil,
        confirmedPrice: Int? = nil,
        adjustmentReason: String? = nil,
        repairProbability: Double? = nil,
        repairConfirmedState: RepairConfirmedState? = RepairConfirmedState.none,
        completenessScore: Double? = nil,
        uncheckedItems: [String] = [],
        checkedItems: [String] = [],
        marketAveragePrice: Int? = nil,
        aiFailureReason: String? = nil,
        syncState: SyncState = .localOnly,
        expiresAt: Date? = nil,
        deletedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.storeId = storeId
        self.staffId = staffId
        self.status = status
        self.vehicle = vehicle
        self.photos = photos
        self.aiResultJSON = aiResultJSON
        self.aiConfidence = aiConfidence
        self.aiProposedPrice = aiProposedPrice
        self.confirmedPrice = confirmedPrice
        self.adjustmentReason = adjustmentReason
        self.repairProbability = repairProbability
        self.repairConfirmedState = repairConfirmedState
        self.completenessScore = completenessScore
        self.uncheckedItems = uncheckedItems
        self.checkedItems = checkedItems
        self.marketAveragePrice = marketAveragePrice
        self.aiFailureReason = aiFailureReason
        self.syncState = syncState
        self.expiresAt = expiresAt
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
