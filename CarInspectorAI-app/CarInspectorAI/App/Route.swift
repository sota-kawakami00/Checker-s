import Foundation

/// 画面遷移の型付きルート（02_SYSTEM_ARCHITECTURE.md §4）
enum Route: Hashable {
    case vehicleInfo(draftId: String?)
    case camera(appraisalId: String)
    case appraisalRunning(appraisalId: String)
    case appraisalResult(appraisalId: String)
    case historyDetail(appraisalId: String)
    case dashboard
    case settings
}
