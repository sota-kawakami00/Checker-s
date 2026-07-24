import Foundation
import Core

/// 履歴の検索・フィルタ（SCREEN_HISTORY.md §15-1: フィルタ判定を集約してUT可能に）。
/// v1 はローカル SwiftData 全件（NFR-03 の 1000件規模）に対するメモリ内判定 + ページング50件。
public enum HistoryFilterEngine {

    public static let pageSize = 50

    /// 修復歴「あり疑い」のしきい値（FR-405 / UC-03 と同値）
    public static let repairSuspectThreshold = ConfirmGuard.repairSuspectThreshold

    public static func matches(
        _ appraisal: Appraisal,
        filter: HistoryFilter,
        vehicleLabel: String
    ) -> Bool {
        if appraisal.deletedAt != nil { return false }

        if !filter.searchText.isEmpty {
            let needle = filter.searchText.lowercased()
            let vinSuffix = appraisal.vehicle.vin?.suffix(6).lowercased() ?? ""
            let haystack = vehicleLabel.lowercased()
            guard haystack.contains(needle) || vinSuffix.contains(needle) else { return false }
        }

        if let from = filter.from, appraisal.createdAt < from { return false }
        if let to = filter.to, appraisal.createdAt >= to { return false }

        if !filter.statuses.isEmpty, !filter.statuses.contains(appraisal.status) { return false }

        if let staffId = filter.staffId, appraisal.staffId != staffId { return false }

        if filter.repairSuspectedOnly {
            guard let probability = appraisal.repairProbability, probability >= repairSuspectThreshold else { return false }
        }

        return true
    }

    public static func page<T>(_ items: [T], page: Int) -> [T] {
        let start = page * pageSize
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + pageSize, items.count)])
    }

    /// BR-05: 期限切れ間近（残り2日以内）の warning 表示判定（SCR-HIS-04）
    public static func isExpiringSoon(_ appraisal: Appraisal, now: Date = .now) -> Bool {
        guard appraisal.status == .confirmed, let expiresAt = appraisal.expiresAt else { return false }
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 && remaining <= 2 * 24 * 3600
    }
}
