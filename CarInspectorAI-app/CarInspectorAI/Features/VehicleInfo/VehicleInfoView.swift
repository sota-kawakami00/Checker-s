import SwiftUI
import Core
import DesignSystem

/// 車両情報入力（SCREEN_VEHICLE_INFO.md）
struct VehicleInfoView: View {
    let draftId: String?
    @Binding var path: [Route]

    @Environment(\.appContainer) private var container
    @State private var viewModel: VehicleInfoViewModel?

    var body: some View {
        Group {
            if let viewModel {
                FormContent(viewModel: viewModel, path: $path, scanAction: { await scanShaken(viewModel) })
            } else {
                Color.clear
            }
        }
        .navigationTitle(Text("vehicle.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = VehicleInfoViewModel(
                    vehicleService: container.vehicleService,
                    appraisalService: container.appraisalService,
                    draftId: draftId
                )
                await viewModel?.onAppear()
            }
        }
    }

    /// 車検証OCR: カメラで1枚撮影して認識（FR-201）
    private func scanShaken(_ viewModel: VehicleInfoViewModel) async {
        guard await container.cameraSession.requestAccess() else { return }
        await container.cameraSession.start()
        guard let frame = try? await container.cameraSession.capturePhoto() else { return }
        await viewModel.scanShaken(image: frame.image)
    }
}

private struct FormContent: View {
    @Bindable var viewModel: VehicleInfoViewModel
    @Binding var path: [Route]
    let scanAction: () async -> Void

    var body: some View {
        Form {
            OCRSection(viewModel: viewModel, scanAction: scanAction)
            BasicInfoSection(viewModel: viewModel)
            EquipmentSection(viewModel: viewModel)
            Section {
                Text("vehicle.autosave.note")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: viewModel.makerCode) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.modelCode) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.gradeCode) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.modelYear) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.vin) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.mileageText) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.colorCode) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.inspectionExpiry) { Task { await viewModel.autosave() } }
        .onChange(of: viewModel.equipments) { Task { await viewModel.autosave() } }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) {
            // 下部固定: 撮影に進む（必須項目充足で活性 SCR-VEH-03）
            PrimaryButton(String(localized: "vehicle.proceed"), isEnabled: viewModel.canProceed) {
                Task {
                    if let appraisalId = await viewModel.proceedToCamera() {
                        path.append(.camera(appraisalId: appraisalId))
                    }
                }
            }
            .accessibilityIdentifier("vehicle.proceed")
            .padding(CIToken.Space.m)
            .background(.bar)
        }
    }
}

/// ① OCRカード（FR-201）
private struct OCRSection: View {
    @Bindable var viewModel: VehicleInfoViewModel
    let scanAction: () async -> Void

    var body: some View {
        Section {
            Button {
                Task { await scanAction() }
            } label: {
                HStack {
                    Image(systemName: "doc.viewfinder")
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(viewModel.ocrAppliedFields.isEmpty ? "vehicle.ocr.scan" : "vehicle.ocr.rescan")
                            .font(CIToken.Fonts.body.bold())
                        Text("vehicle.ocr.hint")
                            .font(CIToken.Fonts.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isScanning {
                        ProgressView()
                    }
                }
            }
            if let message = viewModel.ocrErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(CIToken.Colors.warning)
            }
        }
    }
}

/// ② 基本情報（段階Picker FR-202 / 必須バリデーション）
private struct BasicInfoSection: View {
    @Bindable var viewModel: VehicleInfoViewModel

    var body: some View {
        Section("vehicle.section.basic") {
            makerPickers
            yearPicker
            vinField
            mileageField
            colorPicker
            expiryFields
        }
    }

    @ViewBuilder
    private var makerPickers: some View {
        Picker("vehicle.maker", selection: $viewModel.makerCode) {
            Text("vehicle.select").tag(String?.none)
            ForEach(viewModel.makers) { maker in
                Text(maker.name).tag(String?.some(maker.code))
            }
        }
        .accessibilityIdentifier("vehicle.picker.maker")
        Picker("vehicle.model", selection: $viewModel.modelCode) {
            Text("vehicle.select").tag(String?.none)
            ForEach(viewModel.models) { model in
                Text(model.name).tag(String?.some(model.code))
            }
        }
        .accessibilityIdentifier("vehicle.picker.model")
        .disabled(viewModel.makerCode == nil)
        Picker("vehicle.grade", selection: $viewModel.gradeCode) {
            Text("vehicle.optional").tag(String?.none)
            ForEach(viewModel.grades) { grade in
                Text(grade.name).tag(String?.some(grade.code))
            }
        }
        .disabled(viewModel.modelCode == nil)
    }

    private var availableYears: [Int] {
        if let modelCode = viewModel.modelCode,
           let model = viewModel.models.first(where: { $0.code == modelCode }) {
            return model.years.sorted(by: >)
        }
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array((1970...currentYear).reversed())
    }

    private var yearPicker: some View {
        Picker("vehicle.year", selection: $viewModel.modelYear) {
            Text("vehicle.select").tag(Int?.none)
            ForEach(availableYears, id: \.self) { year in
                Text(verbatim: "\(year)年").tag(Int?.some(year))
            }
        }
        .accessibilityIdentifier("vehicle.picker.year")
        .listRowBackground(highlight("modelYear"))
    }

    @ViewBuilder
    private var vinField: some View {
        HStack {
            Text("vehicle.vin")
            Spacer()
            TextField("vehicle.vin.placeholder", text: $viewModel.vin)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
        .listRowBackground(highlight("vin"))
        if !viewModel.vin.isEmpty {
            Text("vehicle.vin.masked \(VINMasking.mask(viewModel.vin))")
                .font(CIToken.Fonts.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mileageField: some View {
        HStack {
            Text("vehicle.mileage")
            Spacer()
            TextField("0", text: $viewModel.mileageText)
                .accessibilityIdentifier("vehicle.field.mileage")
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(CIToken.Fonts.mono)
            Text(verbatim: "km")
                .foregroundStyle(.secondary)
        }
        if viewModel.fieldErrors.contains(.mileageOutOfRange) {
            Text("vehicle.mileage.error")
                .font(CIToken.Fonts.caption)
                .foregroundStyle(CIToken.Colors.danger)
        }
    }

    private var colorPicker: some View {
        Picker("vehicle.color", selection: $viewModel.colorCode) {
            Text("vehicle.select").tag(String?.none)
            ForEach(viewModel.colors) { color in
                Text(color.label).tag(String?.some(color.code))
            }
        }
        .accessibilityIdentifier("vehicle.picker.color")
    }

    @ViewBuilder
    private var expiryFields: some View {
        Toggle("vehicle.expiry.has", isOn: $viewModel.hasInspectionExpiry)
        if viewModel.hasInspectionExpiry {
            DatePicker(
                "vehicle.expiry",
                selection: Binding(
                    get: { viewModel.inspectionExpiry ?? .now },
                    set: { viewModel.inspectionExpiry = $0 }
                ),
                displayedComponents: .date
            )
            .listRowBackground(highlight("inspectionExpiry"))
            if viewModel.fieldErrors.contains(.expiryInPast) {
                // SCR-VEH-05: 警告のみ、進行は可
                Label("vehicle.expiry.past", systemImage: "exclamationmark.triangle")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(CIToken.Colors.warning)
            }
        }
    }

    /// OCR適用フィールドの warning ハイライト（2sフェードは VM 側で制御）
    @ViewBuilder
    private func highlight(_ field: String) -> some View {
        if viewModel.ocrAppliedFields.contains(field) {
            CIToken.Colors.warning.opacity(0.18)
        } else {
            Color.clear
        }
    }
}

/// ③ 装備チェック（FR-204。Dynamic Type で折返しグリッド、isToggle）
private struct EquipmentSection: View {
    @Bindable var viewModel: VehicleInfoViewModel

    var body: some View {
        Section("vehicle.section.equipments") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: CIToken.Space.s)], spacing: CIToken.Space.s) {
                ForEach(viewModel.equipmentMaster) { equipment in
                    chip(equipment)
                }
            }
        }
    }

    private func chip(_ equipment: EquipmentMaster) -> some View {
        let isOn = viewModel.equipments.contains(equipment.code)
        return Button {
            if isOn {
                viewModel.equipments.remove(equipment.code)
            } else {
                viewModel.equipments.insert(equipment.code)
            }
        } label: {
            HStack(spacing: CIToken.Space.xs) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(equipment.label)
                    .font(CIToken.Fonts.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, CIToken.Space.s)
            .padding(.vertical, CIToken.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isOn ? CIToken.Colors.primary.opacity(0.15) : Color.gray.opacity(0.08),
                in: Capsule()
            )
            .foregroundStyle(isOn ? CIToken.Colors.primary : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}
