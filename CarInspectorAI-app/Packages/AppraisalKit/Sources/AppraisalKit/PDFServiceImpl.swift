import Foundation
import SwiftData
import Core

/// PDFService 実装（FR-502/503）。
/// AI出力そのままの査定書は発行不可 — 確定済み査定のみ生成できる（00 §11-4）。
@MainActor
public final class PDFServiceImpl: PDFService {
    private let context: ModelContext
    private let auth: AuthService
    private let masters: MasterCatalog
    private let storeName: String
    private let renderer = AppraisalSheetRenderer()

    public init(context: ModelContext, auth: AuthService, masters: MasterCatalog, storeName: String) {
        self.context = context
        self.auth = auth
        self.masters = masters
        self.storeName = storeName
    }

    public func generateAppraisalSheet(appraisalId: String) async throws -> URL {
        guard let staff = auth.currentStaff else { throw AppError.unauthenticated }
        var descriptor = FetchDescriptor<Appraisal>(predicate: #Predicate { $0.id == appraisalId })
        descriptor.fetchLimit = 1
        guard let appraisal = try context.fetch(descriptor).first else {
            throw AppError.notFound(entity: "Appraisal")
        }
        // スタッフ確定操作後のみPDF生成可（FR-502）
        guard appraisal.status == .confirmed || appraisal.status == .won || appraisal.status == .lost,
              let confirmedPrice = appraisal.confirmedPrice else {
            throw AppError.validation(reason: "pdfRequiresConfirmed")
        }

        let result: AppraisalResult? = appraisal.aiResultJSON.flatMap { try? AppraisalResult.decode(from: $0) }

        var vehicleLines: [(String, String)] = [
            ("車種", "\(masters.makerName(appraisal.vehicle.makerCode)) \(masters.modelName(appraisal.vehicle.modelCode))")
        ]
        if let year = appraisal.vehicle.modelYear {
            vehicleLines.append(("年式", "\(year)年"))
        }
        vehicleLines.append(("走行距離", "\(appraisal.vehicle.mileageKm.formatted()) km"))
        vehicleLines.append(("カラー", masters.colorLabel(appraisal.vehicle.colorCode)))
        if let vin = appraisal.vehicle.vin {
            // 顧客提示用のためVINはマスク表示（07 §2.1 と同方針）
            vehicleLines.append(("車台番号", VINMasking.mask(vin)))
        }
        if let expiry = appraisal.vehicle.inspectionExpiry {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy年M月d日"
            vehicleLines.append(("車検満了", formatter.string(from: expiry)))
        }

        var repairNote: String?
        if let state = appraisal.repairConfirmedState {
            switch state {
            case .confirmedYes: repairNote = "現車確認の結果、修復歴が確認されています。価格には修復歴を反映済みです。"
            case .confirmedNo: repairNote = "現車確認の結果、修復歴は確認されませんでした。"
            case .unknown: repairNote = "修復歴の有無は現時点で不明です。"
            case .none:
                if let probability = appraisal.repairProbability, probability >= ConfirmGuard.repairSuspectThreshold {
                    repairNote = "修復歴の可能性があります（\(Int(probability * 100))%）。"
                }
            }
        }

        var completenessNote: String?
        if let score = appraisal.completenessScore {
            let unchecked = appraisal.uncheckedItems.compactMap { masters.checkItem($0)?.label }
            completenessNote = unchecked.isEmpty
                ? "査定チェック項目はすべて確認済みです（確認率 \(Int(score * 100))%）。"
                : "確認率 \(Int(score * 100))%。未確認: \(unchecked.joined(separator: "、"))"
        }

        let model = AppraisalSheetRenderer.SheetModel(
            storeName: storeName,
            staffName: staff.displayName,
            issuedAt: .now,
            vehicleLines: vehicleLines,
            confirmedPrice: confirmedPrice,
            tradeInReference: result?.tradeInReference,
            adjustments: result?.adjustments.map { ($0.label, $0.amount) } ?? [],
            basePrice: result?.basePrice,
            marketAveragePrice: appraisal.marketAveragePrice,
            repairNote: repairNote,
            completenessNote: completenessNote,
            expiresAt: appraisal.expiresAt
        )

        let directory = URL.applicationSupportDirectory.appending(path: "pdf", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "appraisal-\(appraisal.id).pdf")
        try renderer.render(model, to: url)

        // 監査ログ（07 §5: PDF生成を記録）
        context.insert(AuditLog(appraisalId: appraisal.id, kind: "pdfGenerated", staffId: staff.id))
        try? context.save()

        return url
    }
}
