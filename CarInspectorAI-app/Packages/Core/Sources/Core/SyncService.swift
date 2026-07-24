import Foundation

/// 同期サービス（06_API_DESIGN.md §1.5 / FR-702）
@MainActor
public protocol SyncService: AnyObject, Sendable {
    /// キュー状態のストリーム（OfflineBanner / 設定画面の同期セクション）
    var queueStatus: AsyncStream<SyncQueueStatus> { get }
    var currentQueueStatus: SyncQueueStatus { get }
    func syncNow() async throws
    func retryFailed() async throws
}
