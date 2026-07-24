import Foundation

/// アプリ全体で統一するエラー型（02_SYSTEM_ARCHITECTURE.md §6）。
/// 全 Service はこの型に変換して throw し、SDK 生エラーを上層へ漏らさない。
public enum AppError: Error, Equatable, Sendable {
    // ネットワーク
    case offline
    case timeout(operation: String)
    case serverError(code: Int)
    // AI
    case aiInvalidResponse(reason: String)   // schema不適合・内訳不整合(BR-02)
    case aiLowConfidence(score: Double)
    case aiQuotaExceeded
    // カメラ/権限
    case cameraPermissionDenied
    case photoQualityCheckFailed
    // データ
    case notFound(entity: String)
    case conflict
    case storageFull
    // 認証
    case unauthenticated
    case forbidden
    // 入力バリデーション（FR-407: 調整理由必須 等。02 §6 への追補提案として導入）
    case validation(reason: String)
}

extension AppError: LocalizedError {
    /// 技術詳細を出さないユーザー向け文言のキー（CLAUDE.md §2.4）。
    /// 表示文言そのものは Localizable.xcstrings（アプリ層）で解決する。
    public var localizationKey: String {
        switch self {
        case .offline: "error.offline"
        case .timeout: "error.timeout"
        case .serverError: "error.server"
        case .aiInvalidResponse: "error.aiInvalidResponse"
        case .aiLowConfidence: "error.aiLowConfidence"
        case .aiQuotaExceeded: "error.aiQuotaExceeded"
        case .cameraPermissionDenied: "error.cameraPermissionDenied"
        case .photoQualityCheckFailed: "error.photoQualityCheckFailed"
        case .notFound: "error.notFound"
        case .conflict: "error.conflict"
        case .storageFull: "error.storageFull"
        case .unauthenticated: "error.unauthenticated"
        case .forbidden: "error.forbidden"
        case .validation: "error.validation"
        }
    }

    public var errorDescription: String? {
        L10n.string(localizationKey)
    }
}
