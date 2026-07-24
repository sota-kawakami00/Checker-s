import Foundation
import Core

/// Gemini メイン査定の出力契約（schemas/appraisal_result.schema.json 準拠）。
/// フィールドの追加・削除・型変更は破壊的変更（AGENTS.md: Schema is Law）。
public struct AppraisalResult: Codable, Equatable, Sendable {
    public var appraisedPrice: Int          // 円・1万円単位（BR-01）
    public var tradeInReference: Int        // 下取参考価格（円）
    public var basePrice: Int               // 相場基準価格（円）
    public var adjustments: [Adjustment]
    public var marketAveragePrice: Int
    public var confidence: Double           // 0-1
    public var needsReview: Bool            // CF付与: 相場乖離大等（省略時 false）
    public var repairFinding: RepairFinding
    public var completeness: Completeness

    enum CodingKeys: String, CodingKey {
        case appraisedPrice, tradeInReference, basePrice, adjustments
        case marketAveragePrice, confidence, needsReview, repairFinding, completeness
    }

    public init(
        appraisedPrice: Int,
        tradeInReference: Int,
        basePrice: Int,
        adjustments: [Adjustment],
        marketAveragePrice: Int,
        confidence: Double,
        needsReview: Bool = false,
        repairFinding: RepairFinding,
        completeness: Completeness
    ) {
        self.appraisedPrice = appraisedPrice
        self.tradeInReference = tradeInReference
        self.basePrice = basePrice
        self.adjustments = adjustments
        self.marketAveragePrice = marketAveragePrice
        self.confidence = confidence
        self.needsReview = needsReview
        self.repairFinding = repairFinding
        self.completeness = completeness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appraisedPrice = try container.decode(Int.self, forKey: .appraisedPrice)
        tradeInReference = try container.decode(Int.self, forKey: .tradeInReference)
        basePrice = try container.decode(Int.self, forKey: .basePrice)
        adjustments = try container.decode([Adjustment].self, forKey: .adjustments)
        marketAveragePrice = try container.decode(Int.self, forKey: .marketAveragePrice)
        confidence = try container.decode(Double.self, forKey: .confidence)
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        repairFinding = try container.decode(RepairFinding.self, forKey: .repairFinding)
        completeness = try container.decode(Completeness.self, forKey: .completeness)
    }
}

public struct Adjustment: Codable, Equatable, Sendable, Identifiable {
    public var code: String                 // 例 popularColor, nonSmoking, panelRepair, tireWear, marketDecline
    public var label: String                // 表示名（日本語）
    public var amount: Int                  // 円。加点は正、減点は負
    public var rationale: String
    public var evidencePhotoIds: [String]

    public var id: String { code }

    public init(code: String, label: String, amount: Int, rationale: String, evidencePhotoIds: [String]) {
        self.code = code
        self.label = label
        self.amount = amount
        self.rationale = rationale
        self.evidencePhotoIds = evidencePhotoIds
    }
}

public struct RepairFinding: Codable, Equatable, Sendable {
    public var probability: Double          // 0-1
    public var evidences: [RepairEvidence]

    public init(probability: Double, evidences: [RepairEvidence]) {
        self.probability = probability
        self.evidences = evidences
    }
}

public enum RepairEvidenceType: String, Codable, Sendable, CaseIterable {
    case toolMarks      // 工具痕
    case colorMismatch  // 色差
    case panelGap       // パネル隙間
    case weldSpots      // スポット溶接痕
    case sealant        // シーラント不自然
}

public struct RepairEvidence: Codable, Equatable, Sendable, Identifiable {
    public var photoId: String
    public var type: RepairEvidenceType
    public var region: NormalizedRegion     // 正規化座標
    public var note: String

    public var id: String { "\(photoId)-\(type.rawValue)-\(region.x)-\(region.y)" }

    public init(photoId: String, type: RepairEvidenceType, region: NormalizedRegion, note: String) {
        self.photoId = photoId
        self.type = type
        self.region = region
        self.note = note
    }
}

/// 正規化座標（0-1）の矩形
public struct NormalizedRegion: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct Completeness: Codable, Equatable, Sendable {
    public var score: Double                // 0-1
    public var uncheckedItems: [UncheckedItem]

    public init(score: Double, uncheckedItems: [UncheckedItem]) {
        self.score = score
        self.uncheckedItems = uncheckedItems
    }
}

public struct UncheckedItem: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var label: String
    public var hint: String

    public var id: String { code }

    public init(code: String, label: String, hint: String) {
        self.code = code
        self.label = label
        self.hint = hint
    }
}

extension AppraisalResult {
    /// 生JSON（監査用原本、04 §2.2 aiResultJSON）からのデコード
    public static func decode(from data: Data) throws -> AppraisalResult {
        do {
            return try JSONDecoder().decode(AppraisalResult.self, from: data)
        } catch {
            throw AppError.aiInvalidResponse(reason: "decode: \(error.localizedDescription)")
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
