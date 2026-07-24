import Foundation
import SwiftData

/// 車両（04_DATA_MODEL.md §2.1）
@Model
public final class Vehicle {
    @Attribute(.unique) public var id: String            // UUID
    public var vin: String?                              // 車台番号
    public var makerCode: String                         // メーカー
    public var modelCode: String                         // 車種
    public var gradeCode: String?                        // グレード
    public var modelYear: Int?                           // 年式（初度登録年）
    public var firstRegistrationYM: String?              // "2021-03"
    public var mileageKm: Int
    public var colorCode: String
    public var inspectionExpiry: Date?                   // 車検満了
    public var equipments: [String]                      // 装備コード配列
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        vin: String? = nil,
        makerCode: String = "",
        modelCode: String = "",
        gradeCode: String? = nil,
        modelYear: Int? = nil,
        firstRegistrationYM: String? = nil,
        mileageKm: Int = 0,
        colorCode: String = "",
        inspectionExpiry: Date? = nil,
        equipments: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.vin = vin
        self.makerCode = makerCode
        self.modelCode = modelCode
        self.gradeCode = gradeCode
        self.modelYear = modelYear
        self.firstRegistrationYM = firstRegistrationYM
        self.mileageKm = mileageKm
        self.colorCode = colorCode
        self.inspectionExpiry = inspectionExpiry
        self.equipments = equipments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum VINMasking {
    /// 車台番号の下6桁をマスクする（07_SECURITY.md §2.1）。6桁未満は全桁マスク。
    public static func mask(_ vin: String) -> String {
        guard vin.count > 6 else { return String(repeating: "*", count: vin.count) }
        return vin.dropLast(6) + "******"
    }
}
