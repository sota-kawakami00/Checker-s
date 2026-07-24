import Foundation
import Core

/// マスタ配信のローカル実装（SCREEN_VEHICLE_INFO.md §15-1: モックJSONで先行実装。
/// M2後半で Firestore `masters/*` 配信 + SwiftData キャッシュ(24h) へ差し替える前提の供給源）。
public struct MasterCatalog: Sendable {
    public let makers: [MakerMaster]
    public let models: [ModelMaster]
    public let equipments: [EquipmentMaster]
    public let checkItems: [CheckItemMaster]
    public let colors: [ColorMaster]

    private struct Payload: Codable {
        var makers: [MakerMaster]
        var models: [ModelMaster]
        var equipments: [EquipmentMaster]
        var checkItems: [CheckItemMaster]
        var colors: [ColorMaster]
    }

    public static func bundled() throws -> MasterCatalog {
        guard let url = Bundle.module.url(forResource: "masters", withExtension: "json") else {
            throw AppError.notFound(entity: "masters.json")
        }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return MasterCatalog(
            makers: payload.makers.sorted { $0.sort < $1.sort },
            models: payload.models,
            equipments: payload.equipments.sorted { $0.sort < $1.sort },
            checkItems: payload.checkItems.sorted { $0.sort < $1.sort },
            colors: payload.colors
        )
    }

    public init(
        makers: [MakerMaster],
        models: [ModelMaster],
        equipments: [EquipmentMaster],
        checkItems: [CheckItemMaster],
        colors: [ColorMaster]
    ) {
        self.makers = makers
        self.models = models
        self.equipments = equipments
        self.checkItems = checkItems
        self.colors = colors
    }

    public func models(makerCode: String) -> [ModelMaster] {
        models.filter { $0.makerCode == makerCode }
    }

    public func grades(makerCode: String, modelCode: String) -> [GradeMaster] {
        models.first { $0.makerCode == makerCode && $0.code == modelCode }?.grades ?? []
    }

    public func makerName(_ code: String) -> String {
        makers.first { $0.code == code }?.name ?? code
    }

    public func modelName(_ code: String) -> String {
        models.first { $0.code == code }?.name ?? code
    }

    public func colorLabel(_ code: String) -> String {
        colors.first { $0.code == code }?.label ?? code
    }

    public func checkItem(_ code: String) -> CheckItemMaster? {
        checkItems.first { $0.code == code }
    }

    /// 査定漏れ診断のスコア再計算（05 §5: score = Σ確認済み重み / Σ全重み）
    public func completenessScore(checkedCodes: Set<String>) -> Double {
        let total = checkItems.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 1 }
        let checked = checkItems.filter { checkedCodes.contains($0.code) }.reduce(0) { $0 + $1.weight }
        return checked / total
    }
}
