import Foundation
import Core
import AppraisalKit

/// AppraisalDTO ⇔ SwiftData 変換（04 §3.2: 変換ロジックはここに集約。他所に書かない）
public enum AppraisalMapper {

    public static func dto(from appraisal: Appraisal) -> AppraisalDTO {
        AppraisalDTO(
            id: appraisal.id,
            storeId: appraisal.storeId,
            staffId: appraisal.staffId,
            status: appraisal.status.rawValue,
            vehicle: AppraisalRequestDTO.VehicleDTO(from: appraisal.vehicle),
            photos: appraisal.photos.map { photo in
                AppraisalDTO.PhotoMeta(
                    photoId: photo.id,
                    angle: photo.angle.rawValue,
                    damageTag: photo.damageTag,
                    storagePath: storagePath(storeId: appraisal.storeId, appraisalId: appraisal.id, photoId: photo.id),
                    qualityPassed: photo.qualityPassed
                )
            },
            aiProposedPrice: appraisal.aiProposedPrice,
            confirmedPrice: appraisal.confirmedPrice,
            adjustmentReason: appraisal.adjustmentReason,
            repairConfirmedState: appraisal.repairConfirmedState?.rawValue,
            checkedItems: appraisal.checkedItems,
            marketAveragePrice: appraisal.marketAveragePrice,
            expiresAt: appraisal.expiresAt,
            deletedAt: appraisal.deletedAt,
            createdAt: appraisal.createdAt,
            updatedAt: appraisal.updatedAt
        )
    }

    /// 競合時のサーバー版適用（02 §5.2: サーバー優先）。写真・AI原本はローカル保持のまま。
    public static func applyServer(_ dto: AppraisalDTO, to appraisal: Appraisal) {
        appraisal.status = AppraisalStatus(rawValue: dto.status) ?? appraisal.status
        appraisal.confirmedPrice = dto.confirmedPrice
        appraisal.adjustmentReason = dto.adjustmentReason
        appraisal.repairConfirmedState = dto.repairConfirmedState.flatMap(RepairConfirmedState.init(rawValue:))
        appraisal.checkedItems = dto.checkedItems
        appraisal.marketAveragePrice = dto.marketAveragePrice
        appraisal.expiresAt = dto.expiresAt
        appraisal.updatedAt = dto.updatedAt
        appraisal.syncState = .synced
    }

    /// Storage パス規約（firestore_collections.md）
    public static func storagePath(storeId: String, appraisalId: String, photoId: String) -> String {
        "stores/\(storeId)/appraisals/\(appraisalId)/photos/\(photoId).jpg"
    }
}
