import Foundation
import Core

/// AI査定結果のクライアント側検証（05_AI_PIPELINE.md §3.3 と同等の検証をクライアントでも実施。
/// 00 §11-3: 内訳合計と価格の整合はクライアントで検証）。
public enum AppraisalResultValidator {

    /// 相場乖離の許容レンジ（05 §3.3-4: 相場平均の 0.3〜1.7倍）
    public static let marketRangeLow = 0.3
    public static let marketRangeHigh = 1.7

    /// 検証を実施し、needsReview を必要に応じて付与した結果を返す。
    /// - Parameters:
    ///   - validPhotoIds: この査定に実在する photoId 集合（evidence 参照検証用）
    ///   - marketAverage: 相場平均。nil の場合レンジ検証はスキップ（相場参考なしモード）
    /// - Throws: `AppError.aiInvalidResponse`（BR-01/BR-02/evidence不整合）
    public static func validate(
        _ result: AppraisalResult,
        validPhotoIds: Set<String>,
        marketAverage: Int?
    ) throws -> AppraisalResult {
        // BR-01: 査定価格は1万円単位
        guard result.appraisedPrice >= 0, result.appraisedPrice % 10_000 == 0 else {
            throw AppError.aiInvalidResponse(reason: "BR-01: appraisedPrice is not in 10,000 yen units")
        }

        // BR-02: 基準価格 + 加減点合計 = 査定価格（1円の不一致も不可）
        let adjustmentTotal = result.adjustments.reduce(0) { $0 + $1.amount }
        guard result.basePrice + adjustmentTotal == result.appraisedPrice else {
            throw AppError.aiInvalidResponse(
                reason: "BR-02: basePrice(\(result.basePrice)) + adjustments(\(adjustmentTotal)) != appraisedPrice(\(result.appraisedPrice))"
            )
        }

        // evidencePhotoIds が実在する photoId を指すこと（05 §3.3-3）
        let referenced = Set(result.adjustments.flatMap(\.evidencePhotoIds))
            .union(result.repairFinding.evidences.map(\.photoId))
        let unknown = referenced.subtracting(validPhotoIds)
        guard unknown.isEmpty else {
            throw AppError.aiInvalidResponse(reason: "evidencePhotoIds reference unknown photos: \(unknown.sorted())")
        }

        // 値域（schema と同等の基本検証）
        guard (0.0...1.0).contains(result.confidence),
              (0.0...1.0).contains(result.repairFinding.probability),
              (0.0...1.0).contains(result.completeness.score) else {
            throw AppError.aiInvalidResponse(reason: "confidence/probability/score out of range")
        }

        // 価格レンジ妥当性: 相場平均の 0.3〜1.7倍の外なら needsReview（エラーにはしない）
        var validated = result
        if let marketAverage, marketAverage > 0 {
            let ratio = Double(result.appraisedPrice) / Double(marketAverage)
            if ratio < marketRangeLow || ratio > marketRangeHigh {
                validated.needsReview = true
            }
        }
        return validated
    }
}
