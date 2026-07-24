import Foundation
import Testing
import Core
@testable import CarInspectorAI

/// 車両情報入力（SCREEN_VEHICLE_INFO §14: SCR-VEH系）
@MainActor
@Suite("VehicleInfoViewModel")
struct VehicleInfoViewModelTests {

    private func makeViewModel(draftId: String? = nil) async throws -> (AppContainer, VehicleInfoViewModel) {
        let container = AppContainer.mock()
        _ = try await container.authService.signIn(email: "staff@carinspector.jp", password: "demo1234")
        let viewModel = VehicleInfoViewModel(
            vehicleService: container.vehicleService,
            appraisalService: container.appraisalService,
            draftId: draftId
        )
        await viewModel.onAppear()
        return (container, viewModel)
    }

    @Test("SCR-VEH-03: 必須未充足では「撮影に進む」非活性")
    func requiredFieldsGateProceed() async throws {
        let (_, viewModel) = try await makeViewModel()
        #expect(!viewModel.canProceed)

        viewModel.makerCode = "toyota"
        viewModel.modelCode = "voxy"
        viewModel.modelYear = 2021
        viewModel.mileageText = "42000"
        #expect(!viewModel.canProceed)   // カラー未選択

        viewModel.colorCode = "pearlWhite"
        #expect(viewModel.canProceed)
    }

    @Test("バリデーション: 走行距離0〜999,999 / 年式1970〜今年（pure function）")
    func validationRules() {
        #expect(VehicleInfoViewModel.validate(mileage: 1_000_000, year: 2021, expiry: nil) == [.mileageOutOfRange])
        #expect(VehicleInfoViewModel.validate(mileage: 42_000, year: 1969, expiry: nil) == [.yearOutOfRange])
        #expect(VehicleInfoViewModel.validate(mileage: 42_000, year: 2100, expiry: nil) == [.yearOutOfRange])
        #expect(VehicleInfoViewModel.validate(mileage: 0, year: 1970, expiry: nil).isEmpty)
    }

    @Test("SCR-VEH-05: 満了日が過去は警告のみで進行可")
    func pastExpiryWarnsButAllows() async throws {
        let (_, viewModel) = try await makeViewModel()
        viewModel.makerCode = "toyota"
        viewModel.modelCode = "voxy"
        viewModel.modelYear = 2021
        viewModel.mileageText = "42000"
        viewModel.colorCode = "pearlWhite"
        viewModel.hasInspectionExpiry = true
        viewModel.inspectionExpiry = Date(timeIntervalSinceNow: -86_400)

        #expect(viewModel.fieldErrors.contains(.expiryInPast))
        #expect(viewModel.canProceed)   // 進行は可
    }

    @Test("SCR-VEH-04: 入力途中の下書きが自動保存され、再開時に全値復元される（FR-205）")
    func draftAutosaveAndRestore() async throws {
        let (container, viewModel) = try await makeViewModel()
        viewModel.makerCode = "toyota"
        viewModel.modelCode = "voxy"
        viewModel.gradeCode = "voxy_s_g"
        viewModel.modelYear = 2021
        viewModel.vin = "ZWR80-1234567"
        viewModel.mileageText = "42000"
        viewModel.colorCode = "pearlWhite"
        viewModel.equipments = ["navi", "etc"]
        await viewModel.autosave()
        let draftId = try #require(viewModel.draft?.id)

        // 強制終了→再開相当: 新しい ViewModel で復元
        let restored = VehicleInfoViewModel(
            vehicleService: container.vehicleService,
            appraisalService: container.appraisalService,
            draftId: draftId
        )
        await restored.onAppear()

        #expect(restored.makerCode == "toyota")
        #expect(restored.modelCode == "voxy")
        #expect(restored.gradeCode == "voxy_s_g")
        #expect(restored.modelYear == 2021)
        #expect(restored.vin == "ZWR80-1234567")
        #expect(restored.mileageText == "42000")
        #expect(restored.colorCode == "pearlWhite")
        #expect(restored.equipments == ["navi", "etc"])
    }

    @Test("マスタ段階ロード: メーカー選択で車種、車種選択でグレードが絞り込まれる（FR-202）")
    func cascadingMasters() async throws {
        let (_, viewModel) = try await makeViewModel()
        #expect(viewModel.makers.count == 9)
        #expect(viewModel.models.isEmpty)

        viewModel.makerCode = "toyota"
        try await Task.sleep(for: .milliseconds(100))
        #expect(!viewModel.models.isEmpty)
        #expect(viewModel.models.allSatisfy { $0.makerCode == "toyota" })

        viewModel.modelCode = "voxy"
        try await Task.sleep(for: .milliseconds(100))
        #expect(!viewModel.grades.isEmpty)

        // メーカー変更で下位選択がリセットされる
        viewModel.makerCode = "nissan"
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.modelCode == nil)
        #expect(viewModel.gradeCode == nil)
    }
}
