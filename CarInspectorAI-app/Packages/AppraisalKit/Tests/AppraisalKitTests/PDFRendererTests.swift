import Foundation
import Testing
import Core
@testable import AppraisalKit

/// 査定書PDF生成（FR-502）
@Suite("AppraisalSheetRenderer")
struct PDFRendererTests {

    @Test("PDFファイルが生成され、PDFヘッダを持つ")
    func rendersPDF() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "test-appraisal-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = AppraisalSheetRenderer.SheetModel(
            storeName: "カーインスペクター東京店",
            staffName: "山田 太郎",
            issuedAt: .now,
            vehicleLines: [("車種", "トヨタ ヴォクシー"), ("走行距離", "42,000 km")],
            confirmedPrice: 1_820_000,
            tradeInReference: 1_900_000,
            adjustments: [("人気カラー", 50_000), ("左前ドア板金", -40_000)],
            basePrice: 1_810_000,
            marketAveragePrice: 1_810_000,
            repairNote: "修復歴は確認されませんでした。",
            completenessNote: "確認率 98%",
            expiresAt: Date().addingTimeInterval(7 * 86_400)
        )
        try AppraisalSheetRenderer().render(model, to: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > 1_000)
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
    }
}
