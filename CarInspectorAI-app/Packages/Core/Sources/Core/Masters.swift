import Foundation

/// マスタ（firestore_collections.md masters/*。読み取り専用配信、FR-202）

public struct MakerMaster: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var name: String
    public var sort: Int
    public var id: String { code }

    public init(code: String, name: String, sort: Int) {
        self.code = code
        self.name = name
        self.sort = sort
    }
}

public struct ModelMaster: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var makerCode: String
    public var name: String
    public var years: [Int]
    public var grades: [GradeMaster]
    public var id: String { code }

    public init(code: String, makerCode: String, name: String, years: [Int], grades: [GradeMaster]) {
        self.code = code
        self.makerCode = makerCode
        self.name = name
        self.years = years
        self.grades = grades
    }
}

public struct GradeMaster: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var name: String
    public var type: String?
    public var id: String { code }

    public init(code: String, name: String, type: String? = nil) {
        self.code = code
        self.name = name
        self.type = type
    }
}

public struct EquipmentMaster: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var label: String
    public var sort: Int
    public var id: String { code }

    public init(code: String, label: String, sort: Int) {
        self.code = code
        self.label = label
        self.sort = sort
    }
}

/// 査定漏れ診断のチェック項目（05_AI_PIPELINE.md §5）
public struct CheckItemMaster: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var label: String
    public var weight: Double
    public var hint: String
    public var sort: Int
    public var id: String { code }

    public init(code: String, label: String, weight: Double, hint: String, sort: Int) {
        self.code = code
        self.label = label
        self.weight = weight
        self.hint = hint
        self.sort = sort
    }
}

public struct ColorMaster: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var label: String
    public var popular: Bool
    public var id: String { code }

    public init(code: String, label: String, popular: Bool) {
        self.code = code
        self.label = label
        self.popular = popular
    }
}
