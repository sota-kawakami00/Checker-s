import Foundation
import Core
import AppraisalKit

/// Firestore ドキュメント形（firestore_collections.md stores/{storeId}/appraisals/{id}）
public struct AppraisalDTO: Codable, Equatable, Sendable {
    public var id: String
    public var storeId: String
    public var staffId: String
    public var status: String
    public var vehicle: AppraisalRequestDTO.VehicleDTO
    public var photos: [PhotoMeta]
    public var aiProposedPrice: Int?
    public var confirmedPrice: Int?
    public var adjustmentReason: String?
    public var repairConfirmedState: String?
    public var checkedItems: [String]
    public var marketAveragePrice: Int?
    public var expiresAt: Date?
    public var deletedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public struct PhotoMeta: Codable, Equatable, Sendable {
        public var photoId: String
        public var angle: String
        public var damageTag: String?
        public var storagePath: String
        public var qualityPassed: Bool
    }
}

/// リモート更新イベント（Firestore スナップショットリスナー相当。02 §8:
/// クライアントは結果を関数レスポンスではなくリスナーで受け取る）
public struct AppraisalRemoteEvent: Sendable {
    public enum Kind: Sendable {
        case running
        case done(AppraisalResult)
        case failed(reason: String)
    }

    public var appraisalId: String
    public var kind: Kind

    public init(appraisalId: String, kind: Kind) {
        self.appraisalId = appraisalId
        self.kind = kind
    }
}

public enum RemoteBackendError: Error {
    /// サーバーと競合。サーバー版を同梱（02 §5.2 conflict）
    case conflict(server: AppraisalDTO)
    case network
    case preconditionNotMet
}

/// Firestore / Storage / Cloud Functions の抽象（02 §5, §8）。
/// 本番実装は Firebase SDK アダプタ（GoogleService-Info.plist 注入後に結線）。
/// 開発・テスト・デモは InMemoryRemoteBackend。
@MainActor
public protocol RemoteBackend: AnyObject, Sendable {
    func uploadAppraisal(_ dto: AppraisalDTO) async throws
    /// マスク済画像のみアップロード可（07 §2.2）。戻り値は remote URL
    func uploadPhoto(data: Data, storagePath: String) async throws -> String
    /// CF runAppraisal（冪等: requestId。結果は appraisalEvents で受信）
    func requestAppraisal(_ request: AppraisalRequestDTO) async throws
    var appraisalEvents: AsyncStream<AppraisalRemoteEvent> { get }
}

/// 接続状態の監視（NFR-05: 復帰後60秒以内に自動同期）
@MainActor
public protocol ConnectivityMonitoring: AnyObject, Sendable {
    var isOnline: Bool { get }
    var events: AsyncStream<Bool> { get }
}

/// テスト・デモ用の手動切替接続モニタ
@MainActor
public final class ManualConnectivity: ConnectivityMonitoring {
    public private(set) var isOnline: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init(online: Bool = true) {
        isOnline = online
    }

    public var events: AsyncStream<Bool> {
        AsyncStream { continuation in
            let token = UUID()
            continuations[token] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: token) }
            }
        }
    }

    public func set(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        for continuation in continuations.values {
            continuation.yield(online)
        }
    }
}

#if canImport(Network)
import Network

/// NWPathMonitor による実接続監視
@MainActor
public final class NetworkPathConnectivity: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    public private(set) var isOnline = true
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                for continuation in self.continuations.values {
                    continuation.yield(online)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }

    public var events: AsyncStream<Bool> {
        AsyncStream { continuation in
            let token = UUID()
            continuations[token] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: token) }
            }
        }
    }
}
#endif
