import Foundation

/// スタッフ認証（06_API_DESIGN.md §1.1 / FR-101〜105）。
/// 本番実装は Firebase Auth。テスト・デモは MockAuthService（SyncKit）。
@MainActor
public protocol AuthService: AnyObject, Sendable {
    var currentStaff: Staff? { get }
    func signIn(email: String, password: String) async throws -> Staff
    func signOut() async throws
    func sendPasswordReset(email: String) async throws
    func observeAuthState() -> AsyncStream<Staff?>
}
