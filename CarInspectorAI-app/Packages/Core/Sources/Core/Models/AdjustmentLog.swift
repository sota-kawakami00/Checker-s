import Foundation
import SwiftData

/// 価格確定・変更の監査ログ（BR-06 / firestore_collections.md adjustmentLogs）。
/// 変更履歴は全件保存し、Firestore の adjustmentLogs サブコレクションへ同期する。
@Model
public final class AdjustmentLog {
    @Attribute(.unique) public var id: String
    public var appraisalId: String
    public var beforePrice: Int?     // 初回確定時は nil（AI提案からの確定）
    public var afterPrice: Int
    public var reason: String?
    public var staffId: String
    public var at: Date
    public var syncState: SyncState

    public init(
        id: String = UUID().uuidString,
        appraisalId: String,
        beforePrice: Int?,
        afterPrice: Int,
        reason: String?,
        staffId: String,
        at: Date = .now,
        syncState: SyncState = .pendingUpload
    ) {
        self.id = id
        self.appraisalId = appraisalId
        self.beforePrice = beforePrice
        self.afterPrice = afterPrice
        self.reason = reason
        self.staffId = staffId
        self.at = at
        self.syncState = syncState
    }
}
