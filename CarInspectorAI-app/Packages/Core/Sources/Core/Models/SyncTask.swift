import Foundation
import SwiftData

/// オフラインキュー（04_DATA_MODEL.md §2.4 / 02 §5.3）
@Model
public final class SyncTask {
    @Attribute(.unique) public var id: String
    public var kind: SyncTaskKind        // uploadAppraisal/uploadPhoto/requestAIAppraisal
    public var targetId: String          // appraisalId or photoId
    public var appraisalId: String       // 同一appraisalIdの直列実行制御（02 §5.3）
    public var retryCount: Int
    public var lastError: String?
    public var state: SyncState
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: SyncTaskKind,
        targetId: String,
        appraisalId: String,
        retryCount: Int = 0,
        lastError: String? = nil,
        state: SyncState = .pendingUpload,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.targetId = targetId
        self.appraisalId = appraisalId
        self.retryCount = retryCount
        self.lastError = lastError
        self.state = state
        self.createdAt = createdAt
    }
}
