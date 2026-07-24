import Foundation
import SwiftData
import Core

/// SwiftData スタック（02 §2: SyncKit の責務）
public enum ModelContainerFactory {

    public static let schema = Schema([
        Vehicle.self,
        Appraisal.self,
        PhotoAsset.self,
        SyncTask.self,
        AdjustmentLog.self,
        AuditLog.self
    ])

    /// 本番: ディスク永続化（オフラインキュー・キャッシュ NFR-04）
    public static func production() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }

    /// テスト / Preview: インメモリ（08 §1: ネットワーク・ディスク非依存）
    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
}
