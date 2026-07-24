import Foundation
import SwiftData

/// 撮影写真（04_DATA_MODEL.md §2.3）
@Model
public final class PhotoAsset {
    @Attribute(.unique) public var id: String
    public var appraisalId: String
    public var angle: PhotoAngle                         // 規定12アングル or .damage(自由撮影)
    public var damageTag: String?                        // 部位タグ（angle == .damage時）
    public var memo: String?                             // damage 撮影の任意メモ（SCREEN_CAMERA §2）
    public var localOriginalPath: String                 // 原本（端末のみ・マスキング前）
    public var localMaskedPath: String?                  // マスキング済（アップロード対象）
    public var remoteURL: String?                        // Storage URL
    public var qualityResultJSON: Data?                  // schemas/photo_quality 準拠
    public var qualityPassed: Bool
    public var maskVerified: Bool                        // 07_SECURITY.md §2.2: 検出失敗時 false
    public var uploadState: UploadState                  // pending/uploading/done/failed
    public var takenAt: Date

    public init(
        id: String = UUID().uuidString,
        appraisalId: String,
        angle: PhotoAngle,
        damageTag: String? = nil,
        memo: String? = nil,
        localOriginalPath: String,
        localMaskedPath: String? = nil,
        remoteURL: String? = nil,
        qualityResultJSON: Data? = nil,
        qualityPassed: Bool = false,
        maskVerified: Bool = true,
        uploadState: UploadState = .pending,
        takenAt: Date = .now
    ) {
        self.id = id
        self.appraisalId = appraisalId
        self.angle = angle
        self.damageTag = damageTag
        self.memo = memo
        self.localOriginalPath = localOriginalPath
        self.localMaskedPath = localMaskedPath
        self.remoteURL = remoteURL
        self.qualityResultJSON = qualityResultJSON
        self.qualityPassed = qualityPassed
        self.maskVerified = maskVerified
        self.uploadState = uploadState
        self.takenAt = takenAt
    }
}
