import Foundation

/// スタッフ（firestore_collections.md stores/{storeId}/staffs）
public struct Staff: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var storeId: String
    public var displayName: String
    public var email: String
    public var role: StaffRole
    public var active: Bool

    public init(id: String, storeId: String, displayName: String, email: String, role: StaffRole, active: Bool = true) {
        self.id = id
        self.storeId = storeId
        self.displayName = displayName
        self.email = email
        self.role = role
        self.active = active
    }
}

/// 店舗（firestore_collections.md stores/{storeId}）
public struct StoreInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var address: String
    public var logoStoragePath: String?
    public var settings: StoreSettings

    public init(id: String, name: String, address: String, logoStoragePath: String? = nil, settings: StoreSettings = .init()) {
        self.id = id
        self.name = name
        self.address = address
        self.logoStoragePath = logoStoragePath
        self.settings = settings
    }
}

public struct StoreSettings: Codable, Equatable, Sendable {
    public var targetMarginRate: Double?
    public var forceAppLock: Bool
    public var promptVariant: String?

    public init(targetMarginRate: Double? = nil, forceAppLock: Bool = false, promptVariant: String? = nil) {
        self.targetMarginRate = targetMarginRate
        self.forceAppLock = forceAppLock
        self.promptVariant = promptVariant
    }
}
