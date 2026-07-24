import Foundation
import CoreGraphics
import Core
@preconcurrency import Vision

/// VehicleService 実装（06 §1.2）。
/// OCR は Vision（VNRecognizeTextRequest, accurate, ja対応）+ ShakenOCRParser（SCREEN_VEHICLE_INFO §9）。
@MainActor
public final class VehicleServiceImpl: VehicleService {
    private let masters: MasterCatalog

    public init(masters: MasterCatalog) {
        self.masters = masters
    }

    public func recognizeShaken(from image: CGImage) async throws -> ShakenOCRResult {
        let lines = try await Self.recognizeText(in: image)
        let result = ShakenOCRParser.parse(lines: lines)
        // OCR不能（1フィールドも取れない）はエラーにしてフォームへフォールバック（SCREEN_VEHICLE_INFO §10）
        if result.vin == nil, result.katashiki == nil,
           result.firstRegistrationYM == nil, result.inspectionExpiry == nil,
           result.lowConfidenceFields.isEmpty {
            throw AppError.validation(reason: "ocrUnreadable")
        }
        return result
    }

    /// Vision テキスト認識（バックグラウンド実行、UIブロック禁止）
    nonisolated static func recognizeText(in image: CGImage) async throws -> [ShakenOCRParser.RecognizedLine] {
        let sendableImage = image
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: sendableImage, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { observation -> ShakenOCRParser.RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return ShakenOCRParser.RecognizedLine(text: candidate.string, confidence: Double(candidate.confidence))
            }
        }.value
    }

    public func makers() async throws -> [MakerMaster] {
        masters.makers
    }

    public func models(makerCode: String) async throws -> [ModelMaster] {
        masters.models(makerCode: makerCode)
    }

    public func grades(makerCode: String, modelCode: String) async throws -> [GradeMaster] {
        masters.grades(makerCode: makerCode, modelCode: modelCode)
    }

    public func equipmentMaster() async throws -> [EquipmentMaster] {
        masters.equipments
    }

    public func colorMaster() async throws -> [ColorMaster] {
        masters.colors
    }
}
