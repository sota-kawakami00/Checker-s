import Foundation
import Core
import AppraisalKit

/// Firestore/Storage/CF のローカル模擬実装。
/// - 08_TEST_PLAN §1「録画リプレイ方式」: examples/ の固定JSONを土台に、実在 photoId に合わせて返す
/// - runAppraisal の価格生成は CF/Gemini 側の模擬であり、クライアント実装の価格ロジックではない
///   （CLAUDE.md §2.3 の禁止事項はクライアント本体に適用。Firebase 結線時は本クラスを差し替える）
@MainActor
public final class InMemoryRemoteBackend: RemoteBackend {

    public private(set) var uploadedAppraisals: [String: AppraisalDTO] = [:]
    public private(set) var uploadedPhotos: [String: Data] = [:]
    public private(set) var appraisalRequests: [AppraisalRequestDTO] = []
    private var processedRequestIds: Set<String> = []

    // テスト用の障害・遅延・競合注入
    public var uploadFailuresRemaining = 0
    public var conflictOnNextUpload: AppraisalDTO?
    public var failNextAppraisalReason: String?
    public var appraisalDelay: Duration

    private var eventContinuations: [UUID: AsyncStream<AppraisalRemoteEvent>.Continuation] = [:]

    public init(appraisalDelay: Duration = .seconds(2.5)) {
        self.appraisalDelay = appraisalDelay
    }

    public var appraisalEvents: AsyncStream<AppraisalRemoteEvent> {
        AsyncStream { continuation in
            let token = UUID()
            eventContinuations[token] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in self?.eventContinuations.removeValue(forKey: token) }
            }
        }
    }

    private func emit(_ event: AppraisalRemoteEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    public func uploadAppraisal(_ dto: AppraisalDTO) async throws {
        if uploadFailuresRemaining > 0 {
            uploadFailuresRemaining -= 1
            throw RemoteBackendError.network
        }
        if let server = conflictOnNextUpload {
            conflictOnNextUpload = nil
            throw RemoteBackendError.conflict(server: server)
        }
        uploadedAppraisals[dto.id] = dto
    }

    public func uploadPhoto(data: Data, storagePath: String) async throws -> String {
        if uploadFailuresRemaining > 0 {
            uploadFailuresRemaining -= 1
            throw RemoteBackendError.network
        }
        uploadedPhotos[storagePath] = data
        return "https://storage.local/\(storagePath)"
    }

    public func requestAppraisal(_ request: AppraisalRequestDTO) async throws {
        // 冪等（06 §2.1: 同一 requestId は再実行せず accepted）
        guard !processedRequestIds.contains(request.requestId) else { return }
        processedRequestIds.insert(request.requestId)
        appraisalRequests.append(request)

        emit(AppraisalRemoteEvent(appraisalId: request.appraisalId, kind: .running))

        if let reason = failNextAppraisalReason {
            failNextAppraisalReason = nil
            let delay = appraisalDelay
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                self?.emit(AppraisalRemoteEvent(appraisalId: request.appraisalId, kind: .failed(reason: reason)))
            }
            return
        }

        let delay = appraisalDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            let result = MockAppraisalComposer.compose(for: request)
            self.emit(AppraisalRemoteEvent(appraisalId: request.appraisalId, kind: .done(result)))
        }
    }
}

/// examples/appraisal_result.example.json を土台に、リクエスト内容へ整合させた結果を合成する
/// （CF runAppraisal + Gemini の模擬。BR-01/BR-02 を満たす出力のみ生成する）
public enum MockAppraisalComposer {

    public static func compose(for request: AppraisalRequestDTO) -> AppraisalResult {
        let template = loadTemplate()

        // 車両条件から基準価格を決定（相場APIの模擬）
        let year = request.vehicle.modelYear ?? 2020
        let age = max(0, 2026 - year)
        let mileagePenalty = request.vehicle.mileageKm / 1000 * 8_000
        var base = 2_600_000 - age * 180_000 - mileagePenalty
        base = max(300_000, (base / 10_000) * 10_000)

        // 実在する photoId のみを根拠として参照（05 §3.3-3 を満たす）
        let photoIds = request.photos.map(\.photoId)
        func evidence(_ preferredAngles: [String]) -> [String] {
            for angle in preferredAngles {
                if let hit = request.photos.first(where: { $0.angle == angle }) {
                    return [hit.photoId]
                }
            }
            return photoIds.prefix(1).map { $0 }
        }

        var adjustments: [Adjustment] = []
        for adjustment in template.adjustments {
            var copied = adjustment
            switch adjustment.code {
            case "popularColor":
                guard ["pearlWhite", "black"].contains(request.vehicle.colorCode) else { continue }
                copied.evidencePhotoIds = evidence(["front"])
            case "nonSmoking":
                copied.evidencePhotoIds = evidence(["interiorFront", "interiorRear"])
            case "panelRepair":
                copied.evidencePhotoIds = evidence(["left", "damage"])
            case "tireWear":
                copied.evidencePhotoIds = evidence(["frontLeft", "frontRight"])
            default:
                copied.evidencePhotoIds = []
            }
            adjustments.append(copied)
        }

        // 修復歴「あり」確定時は修復歴ありの相場で再計算（BR-04 の模擬）
        var repairProbability = template.repairFinding.probability
        if request.repairConfirmed == true {
            adjustments.append(Adjustment(
                code: "repairHistory",
                label: "修復歴あり（現車確認済）",
                amount: -150_000,
                rationale: "現車確認により修復歴が確定したため、修復歴ありの相場で評価しています。",
                evidencePhotoIds: evidence(["engineRoom", "frontRight"])
            ))
            repairProbability = 1.0
        } else if request.repairConfirmed == false {
            repairProbability = 0.05
        }

        let appraised = base + adjustments.reduce(0) { $0 + $1.amount }   // BR-02 を構成的に満たす

        // 査定漏れ診断: 画像に写り得ない項目を unchecked に残す（05 §5）
        let photoUnverifiable: Set<String> = ["spareKey", "maintenanceBook", "underbody", "airCondition", "engineStart"]
        let unchecked = request.checkItems
            .filter { photoUnverifiable.contains($0.code) }
            .map { item in
                UncheckedItem(
                    code: item.code,
                    label: item.label,
                    hint: hintFor(item.code)
                )
            }
        let totalWeight = request.checkItems.reduce(0) { $0 + $1.weight }
        let uncheckedWeight = request.checkItems
            .filter { item in unchecked.contains { $0.code == item.code } }
            .reduce(0) { $0 + $1.weight }
        let score = totalWeight > 0 ? (totalWeight - uncheckedWeight) / totalWeight : 1

        // 情報充足度で信頼度を決める（写真12枚未満・主要項目 null は減点。00 §11 / プロンプト規約）
        var confidence = 0.94
        if request.photos.count < 12 { confidence -= 0.22 }
        if request.vehicle.modelYear == nil { confidence -= 0.1 }
        if request.vehicle.gradeCode == nil { confidence -= 0.04 }

        let repairEvidences: [RepairEvidence] = repairProbability >= 0.5
            ? [
                RepairEvidence(
                    photoId: evidence(["engineRoom", "frontRight"]).first ?? photoIds.first ?? "",
                    type: .toolMarks,
                    region: NormalizedRegion(x: 0.12, y: 0.34, w: 0.18, h: 0.12),
                    note: "右フェンダー取付ボルトに工具を掛けた痕の可能性があります。"
                )
            ]
            : template.repairFinding.evidences.compactMap { evidenceItem in
                guard let photoId = evidence(["left", "damage"]).first else { return nil }
                var copied = evidenceItem
                copied.photoId = photoId
                return copied
            }

        return AppraisalResult(
            appraisedPrice: appraised,
            tradeInReference: appraised + 80_000,
            basePrice: base,
            adjustments: adjustments,
            marketAveragePrice: base + 10_000,
            confidence: max(0.3, confidence),
            needsReview: false,
            repairFinding: RepairFinding(probability: repairProbability, evidences: repairEvidences),
            completeness: Completeness(score: score, uncheckedItems: unchecked)
        )
    }

    private static func hintFor(_ code: String) -> String {
        switch code {
        case "spareKey": "お客様にスペアキーの有無をご確認ください。"
        case "maintenanceBook": "グローブボックス内をご確認ください。"
        case "underbody": "リフトアップまたはミラーで下回りをご確認ください。"
        case "airCondition": "冷房・暖房の効きをご確認ください。"
        case "engineStart": "エンジンをかけ、異音・警告灯をご確認ください。"
        default: "現車でご確認ください。"
        }
    }

    private static func loadTemplate() -> AppraisalResult {
        guard let url = Bundle.module.url(forResource: "appraisal_result.example", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? AppraisalResult.decode(from: data) else {
            // リソース破損時のフォールバック（テンプレートなしでも構成的に成立させる）
            return AppraisalResult(
                appraisedPrice: 0,
                tradeInReference: 0,
                basePrice: 0,
                adjustments: [],
                marketAveragePrice: 0,
                confidence: 0.5,
                repairFinding: RepairFinding(probability: 0.1, evidences: []),
                completeness: Completeness(score: 1, uncheckedItems: [])
            )
        }
        return result
    }
}
