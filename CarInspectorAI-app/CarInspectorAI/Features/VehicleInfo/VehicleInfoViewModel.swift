import Foundation
import Observation
import CoreGraphics
import Core
import AppraisalKit

/// 車両情報入力（SCREEN_VEHICLE_INFO.md §4）
@MainActor
@Observable
final class VehicleInfoViewModel {

    enum FieldError: Equatable {
        case mileageOutOfRange      // 0〜999,999
        case yearOutOfRange         // 1970〜今年
        case expiryInPast           // 警告（進行は可）
    }

    // フォーム状態
    var makerCode: String? {
        didSet { if oldValue != makerCode { modelCode = nil; gradeCode = nil; Task { await loadModels() } } }
    }
    var modelCode: String? {
        didSet { if oldValue != modelCode { gradeCode = nil; Task { await loadGrades() } } }
    }
    var gradeCode: String?
    var modelYear: Int?
    var vin = ""
    var mileageText = ""
    var colorCode: String?
    var inspectionExpiry: Date?
    var hasInspectionExpiry = false
    var equipments: Set<String> = []

    // OCR
    private(set) var isScanning = false
    private(set) var ocrAppliedFields: Set<String> = []   // 適用フィールドのハイライト（2sでフェード）
    private(set) var ocrErrorMessage: String?

    // マスタ
    private(set) var makers: [MakerMaster] = []
    private(set) var models: [ModelMaster] = []
    private(set) var grades: [GradeMaster] = []
    private(set) var equipmentMaster: [EquipmentMaster] = []
    private(set) var colors: [ColorMaster] = []

    private(set) var draft: Appraisal?
    private(set) var isSaving = false

    private let vehicleService: any VehicleService
    private let appraisalService: any AppraisalService
    private let draftId: String?

    init(vehicleService: any VehicleService, appraisalService: any AppraisalService, draftId: String?) {
        self.vehicleService = vehicleService
        self.appraisalService = appraisalService
        self.draftId = draftId
    }

    // MARK: - ロード

    func onAppear() async {
        do {
            makers = try await vehicleService.makers()
            equipmentMaster = try await vehicleService.equipmentMaster()
            colors = try await vehicleService.colorMaster()
        } catch {
            // マスタ取得失敗: 入力に進めない旨は View 側表示（SCREEN_VEHICLE_INFO §10）
        }
        if let draftId {
            await restoreDraft(id: draftId)
        }
    }

    private func restoreDraft(id: String) async {
        guard let existing = try? await appraisalService.appraisal(id: id) else { return }
        draft = existing
        let vehicle = existing.vehicle
        makerCode = vehicle.makerCode.isEmpty ? nil : vehicle.makerCode
        await loadModels()
        modelCode = vehicle.modelCode.isEmpty ? nil : vehicle.modelCode
        await loadGrades()
        gradeCode = vehicle.gradeCode
        modelYear = vehicle.modelYear
        vin = vehicle.vin ?? ""
        mileageText = vehicle.mileageKm > 0 ? String(vehicle.mileageKm) : ""
        colorCode = vehicle.colorCode.isEmpty ? nil : vehicle.colorCode
        inspectionExpiry = vehicle.inspectionExpiry
        hasInspectionExpiry = vehicle.inspectionExpiry != nil
        equipments = Set(vehicle.equipments)
    }

    private func loadModels() async {
        guard let makerCode else {
            models = []
            return
        }
        models = (try? await vehicleService.models(makerCode: makerCode)) ?? []
    }

    private func loadGrades() async {
        guard let makerCode, let modelCode else {
            grades = []
            return
        }
        grades = (try? await vehicleService.grades(makerCode: makerCode, modelCode: modelCode)) ?? []
    }

    // MARK: - OCR（FR-201）

    func scanShaken(image: CGImage) async {
        isScanning = true
        ocrErrorMessage = nil
        defer { isScanning = false }
        do {
            let result = try await vehicleService.recognizeShaken(from: image)
            var applied: Set<String> = []
            if let recognizedVIN = result.vin {
                vin = recognizedVIN
                applied.insert("vin")
            }
            if let ym = result.firstRegistrationYM, let year = Int(ym.prefix(4)) {
                modelYear = year
                applied.insert("modelYear")
            }
            if let expiry = result.inspectionExpiry {
                inspectionExpiry = expiry
                hasInspectionExpiry = true
                applied.insert("inspectionExpiry")
            }
            ocrAppliedFields = applied
            await autosave()
            // ハイライトは2秒でフェード（SCREEN_VEHICLE_INFO §11）
            try? await Task.sleep(for: .seconds(2))
            ocrAppliedFields = []
        } catch {
            // OCR不能: 手入力へフォールバック（SCR-VEH-02/§10）
            ocrErrorMessage = String(localized: "vehicle.ocr.failed")
        }
    }

    // MARK: - バリデーション（pure、SCREEN_VEHICLE_INFO §15-3）

    var mileageKm: Int? { Int(mileageText) }

    static func validate(
        mileage: Int?,
        year: Int?,
        expiry: Date?,
        now: Date = .now
    ) -> [FieldError] {
        var errors: [FieldError] = []
        if let mileage, !(0...999_999).contains(mileage) {
            errors.append(.mileageOutOfRange)
        }
        let currentYear = Calendar.current.component(.year, from: now)
        if let year, !(1970...currentYear).contains(year) {
            errors.append(.yearOutOfRange)
        }
        if let expiry, expiry < now {
            errors.append(.expiryInPast)   // 警告のみ（SCR-VEH-05: 進行は可）
        }
        return errors
    }

    var fieldErrors: [FieldError] {
        Self.validate(mileage: mileageText.isEmpty ? nil : (mileageKm ?? -1), year: modelYear, expiry: hasInspectionExpiry ? inspectionExpiry : nil)
    }

    /// 必須: メーカー/車種/年式/走行距離/カラー（SCREEN_VEHICLE_INFO §2）
    var canProceed: Bool {
        guard makerCode != nil, modelCode != nil, modelYear != nil, colorCode != nil,
              let mileage = mileageKm, (0...999_999).contains(mileage) else { return false }
        return !fieldErrors.contains(.yearOutOfRange)
    }

    // MARK: - 下書き保存（FR-205: 全変更を即時保存）

    func autosave() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let draft {
                apply(to: draft.vehicle)
                try await appraisalService.updateDraft(draft)
            } else if makerCode != nil || modelCode != nil || !vin.isEmpty || !mileageText.isEmpty {
                let vehicle = Vehicle()
                apply(to: vehicle)
                draft = try await appraisalService.createDraft(vehicle: vehicle)
            }
        } catch {
            // 保存失敗は次回変更時に再試行（下書きはローカルのみ）
        }
    }

    private func apply(to vehicle: Vehicle) {
        vehicle.makerCode = makerCode ?? ""
        vehicle.modelCode = modelCode ?? ""
        vehicle.gradeCode = gradeCode
        vehicle.modelYear = modelYear
        vehicle.vin = vin.isEmpty ? nil : vin
        vehicle.mileageKm = mileageKm ?? 0
        vehicle.colorCode = colorCode ?? ""
        vehicle.inspectionExpiry = hasInspectionExpiry ? inspectionExpiry : nil
        vehicle.equipments = Array(equipments)
        vehicle.updatedAt = .now
    }

    /// 撮影へ進む（SCREEN_VEHICLE_INFO §4）
    func proceedToCamera() async -> String? {
        guard canProceed else { return nil }
        await autosave()
        return draft?.id
    }
}
