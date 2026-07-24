import Foundation
import SwiftData

/// 操作監査ログ（07_SECURITY.md §5 / firestore_collections.md auditLogs）
@Model
public final class AuditLog {
    @Attribute(.unique) public var id: String
    public var appraisalId: String
    public var kind: String          // pdfGenerated / exported / ...
    public var staffId: String
    public var at: Date
    public var syncState: SyncState

    public init(
        id: String = UUID().uuidString,
        appraisalId: String,
        kind: String,
        staffId: String,
        at: Date = .now,
        syncState: SyncState = .pendingUpload
    ) {
        self.id = id
        self.appraisalId = appraisalId
        self.kind = kind
        self.staffId = staffId
        self.at = at
        self.syncState = syncState
    }
}
