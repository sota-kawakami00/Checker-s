import Foundation
import Core

/// デモ・開発用の認証実装（FR-101〜105 の動作確認用。本番は Firebase Auth アダプタに差し替え）。
/// デモアカウント: staff@carinspector.jp / manager@carinspector.jp（パスワード: demo1234）
@MainActor
public final class MockAuthService: AuthService {

    public static let demoPassword = "demo1234"

    private static let accounts: [String: Staff] = [
        "staff@carinspector.jp": Staff(
            id: "staff-demo",
            storeId: "store-demo",
            displayName: "佐藤 花子",
            email: "staff@carinspector.jp",
            role: .staff
        ),
        "manager@carinspector.jp": Staff(
            id: "manager-demo",
            storeId: "store-demo",
            displayName: "山田 太郎",
            email: "manager@carinspector.jp",
            role: .manager
        )
    ]

    private static let persistKey = "carinspector.auth.email"

    public private(set) var currentStaff: Staff?
    private var continuations: [UUID: AsyncStream<Staff?>.Continuation] = [:]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let email = defaults.string(forKey: Self.persistKey) {
            currentStaff = Self.accounts[email]
        }
    }

    public func signIn(email: String, password: String) async throws -> Staff {
        let normalized = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let staff = Self.accounts[normalized], password == Self.demoPassword else {
            throw AppError.unauthenticated
        }
        guard staff.active else { throw AppError.forbidden }
        currentStaff = staff
        defaults.set(normalized, forKey: Self.persistKey)
        broadcast()
        return staff
    }

    public func signOut() async throws {
        currentStaff = nil
        defaults.removeObject(forKey: Self.persistKey)
        broadcast()
    }

    public func sendPasswordReset(email: String) async throws {
        // FR-105: 本番は Firebase Auth のリセットメール。デモではアカウント存在確認のみ
        guard Self.accounts[email.lowercased()] != nil else {
            throw AppError.notFound(entity: "account")
        }
    }

    public func observeAuthState() -> AsyncStream<Staff?> {
        AsyncStream { continuation in
            let token = UUID()
            continuations[token] = continuation
            continuation.yield(currentStaff)
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: token) }
            }
        }
    }

    private func broadcast() {
        for continuation in continuations.values {
            continuation.yield(currentStaff)
        }
    }
}
