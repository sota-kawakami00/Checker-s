import Foundation

/// 査定ステータス（04_DATA_MODEL.md §2.2 / FR-504）
public enum AppraisalStatus: String, Codable, Sendable, CaseIterable {
    case draft, aiRunning, aiCompleted, confirmed, won, lost, expired
}

/// 同期状態（02_SYSTEM_ARCHITECTURE.md §5.2）
public enum SyncState: String, Codable, Sendable {
    case localOnly       // 下書き。まだ同期対象外
    case pendingUpload   // アップロード待ち（オフラインキュー）
    case uploading
    case synced
    case conflict        // サーバーと競合。サーバー版採用+ローカルを退避コピー
    case failed          // リトライ上限到達。手動再送UI（FR-702）
}

/// 修復歴の人間確認状態（04_DATA_MODEL.md §2.2 / UC-03）
public enum RepairConfirmedState: String, Codable, Sendable {
    case none, confirmedYes, confirmedNo, unknown
}

/// 撮影アングル（04_DATA_MODEL.md §2.3 / FR-301）
public enum PhotoAngle: String, Codable, Sendable, CaseIterable {
    case front, rear, left, right
    case frontLeft, frontRight, rearLeft, rearRight
    case interiorFront, interiorRear
    case meter, engineRoom
    case damage                                   // 自由撮影

    /// 規定12アングル（damage を除く、撮影ガイド順）
    public static let guided: [PhotoAngle] = [
        .front, .frontRight, .right, .rearRight,
        .rear, .rearLeft, .left, .frontLeft,
        .interiorFront, .interiorRear, .meter, .engineRoom
    ]

    /// アングル名の xcstrings キー
    public var localizationKey: String { "angle.\(rawValue)" }
}

/// 画像アップロード状態（04_DATA_MODEL.md §2.3）
public enum UploadState: String, Codable, Sendable {
    case pending, uploading, done, failed
}

/// オフラインキューのタスク種別（04_DATA_MODEL.md §2.4）
public enum SyncTaskKind: String, Codable, Sendable {
    case uploadAppraisal, uploadPhoto, requestAIAppraisal
}

/// スタッフ権限（FR-103）
public enum StaffRole: String, Codable, Sendable, Comparable {
    case staff, manager, admin

    private var rank: Int {
        switch self {
        case .staff: 0
        case .manager: 1
        case .admin: 2
        }
    }

    public static func < (lhs: StaffRole, rhs: StaffRole) -> Bool { lhs.rank < rhs.rank }
}
