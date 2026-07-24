import Foundation
import Testing
@testable import AppraisalKit

/// 車検証OCR抽出規則（SCREEN_VEHICLE_INFO §15-2 / SCR-VEH-01/02）
@Suite("ShakenOCRParser")
struct ShakenOCRParserTests {

    private func line(_ text: String, _ confidence: Double = 0.95) -> ShakenOCRParser.RecognizedLine {
        .init(text: text, confidence: confidence)
    }

    @Test("SCR-VEH-01: 正常車検証OCRで4項目が抽出される")
    func normalShaken() {
        let result = ShakenOCRParser.parse(lines: [
            line("自動車検査証"),
            line("初度登録年月 令和3年3月"),
            line("車台番号 ZWR80-1234567"),
            line("型式 6AA-ZWR80W"),
            line("有効期間の満了する日 令和8年3月14日")
        ])
        #expect(result.vin == "ZWR80-1234567")
        #expect(result.katashiki == "6AA-ZWR80W")
        #expect(result.firstRegistrationYM == "2021-03")
        #expect(result.inspectionExpiry != nil)
        #expect(result.lowConfidenceFields.isEmpty)

        let calendar = Calendar(identifier: .gregorian)
        var timeZoneCalendar = calendar
        timeZoneCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        if let expiry = result.inspectionExpiry {
            let components = timeZoneCalendar.dateComponents([.year, .month, .day], from: expiry)
            #expect(components.year == 2026)
            #expect(components.month == 3)
            #expect(components.day == 14)
        }
    }

    @Test("SCR-VEH-02: 低信頼フィールドは適用せず lowConfidenceFields に記録")
    func lowConfidenceNotApplied() {
        let result = ShakenOCRParser.parse(lines: [
            line("車台番号 ZWR80-1234567", 0.3),   // 低信頼
            line("型式 6AA-ZWR80W", 0.9)
        ])
        #expect(result.vin == nil)
        #expect(result.lowConfidenceFields.contains("vin"))
        #expect(result.katashiki == "6AA-ZWR80W")
    }

    @Test("平成表記の初度登録も西暦に変換される")
    func heiseiConversion() {
        let result = ShakenOCRParser.parse(lines: [line("初度登録年月 平成30年11月")])
        #expect(result.firstRegistrationYM == "2018-11")
    }

    @Test("全角数字・ラベルなし行のフォールバック")
    func fullWidthAndLabelless() {
        let result = ShakenOCRParser.parse(lines: [
            line("初度登録年月　令和２年１２月"),
            line("ＺＷＲ８０－７６５４３２１")
        ])
        #expect(result.firstRegistrationYM == "2020-12")
        #expect(result.vin == "ZWR80-7654321")
    }

    @Test("非車検証（無関係テキスト）は何も抽出しない")
    func unrelatedText() {
        let result = ShakenOCRParser.parse(lines: [line("本日は晴天なり"), line("駐車場のご案内")])
        #expect(result.vin == nil)
        #expect(result.katashiki == nil)
        #expect(result.firstRegistrationYM == nil)
        #expect(result.inspectionExpiry == nil)
    }
}
