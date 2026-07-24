import Foundation
import Core

/// 車検証OCRの抽出規則（SCREEN_VEHICLE_INFO.md §15-2: パーサを分離してUT可能に）。
/// Vision の認識行（文字列+信頼度）を受け取り、車台番号/型式/初度登録/満了日を抽出する。
public enum ShakenOCRParser {

    public struct RecognizedLine: Sendable, Equatable {
        public var text: String
        public var confidence: Double  // 0-1

        public init(text: String, confidence: Double) {
            self.text = text
            self.confidence = confidence
        }
    }

    /// 信頼度がこの値未満のフィールドは自動適用しない（SCR-VEH-02）
    public static let confidenceFloor = 0.6

    public static func parse(lines: [RecognizedLine]) -> ShakenOCRResult {
        var result = ShakenOCRResult()

        for line in lines {
            let text = normalize(line.text)

            if result.vin == nil, let vin = extractVIN(from: text) {
                if line.confidence >= confidenceFloor {
                    result.vin = vin
                } else {
                    result.lowConfidenceFields.append("vin")
                }
            }
            if result.katashiki == nil, let katashiki = extractKatashiki(from: text) {
                if line.confidence >= confidenceFloor {
                    result.katashiki = katashiki
                } else {
                    result.lowConfidenceFields.append("katashiki")
                }
            }
            if result.firstRegistrationYM == nil, let ym = extractFirstRegistration(from: text) {
                if line.confidence >= confidenceFloor {
                    result.firstRegistrationYM = ym
                } else {
                    result.lowConfidenceFields.append("firstRegistrationYM")
                }
            }
            if result.inspectionExpiry == nil, let date = extractExpiry(from: text) {
                if line.confidence >= confidenceFloor {
                    result.inspectionExpiry = date
                } else {
                    result.lowConfidenceFields.append("inspectionExpiry")
                }
            }
        }
        return result
    }

    static func normalize(_ text: String) -> String {
        text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
    }

    /// 車台番号: 「車台番号」ラベル行 or 型式-連番形式（例 ZWR80-1234567）
    static func extractVIN(from text: String) -> String? {
        let pattern = /([A-Z0-9]{3,8})-([0-9]{6,8})/
        if text.contains("車台番号") {
            if let match = text.firstMatch(of: pattern) {
                return "\(match.1)-\(match.2)"
            }
        }
        // ラベルなし行でも車台番号形式に合致すれば候補とする
        if let match = text.wholeMatch(of: pattern) {
            return "\(match.1)-\(match.2)"
        }
        return nil
    }

    /// 型式: 「型式」ラベル + 例 6AA-ZWR90W / DBA-ZRR80G
    static func extractKatashiki(from text: String) -> String? {
        guard text.contains("型式"), !text.contains("原動機") else { return nil }
        if let match = text.firstMatch(of: /([0-9A-Z]{2,3})-([A-Z0-9]{4,8})/) {
            return "\(match.1)-\(match.2)"
        }
        return nil
    }

    /// 初度登録年月: 「初度登録年月」+ 令和/平成/西暦 → "yyyy-MM"
    static func extractFirstRegistration(from text: String) -> String? {
        guard text.contains("初度登録") else { return nil }
        return parseJapaneseYearMonth(text)
    }

    /// 有効期間の満了する日: 「有効期間」→ Date
    static func extractExpiry(from text: String) -> Date? {
        guard text.contains("有効期間") else { return nil }
        guard let ymd = parseJapaneseYearMonthDay(text) else { return nil }
        var components = DateComponents()
        components.year = ymd.year
        components.month = ymd.month
        components.day = ymd.day
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return components.date
    }

    static func parseJapaneseYearMonth(_ text: String) -> String? {
        if let match = text.firstMatch(of: /令和\s*([0-9]{1,2})年\s*([0-9]{1,2})月/) {
            guard let era = Int(match.1), let month = Int(match.2) else { return nil }
            return String(format: "%04d-%02d", 2018 + era, month)
        }
        if let match = text.firstMatch(of: /平成\s*([0-9]{1,2})年\s*([0-9]{1,2})月/) {
            guard let era = Int(match.1), let month = Int(match.2) else { return nil }
            return String(format: "%04d-%02d", 1988 + era, month)
        }
        if let match = text.firstMatch(of: /([12][0-9]{3})年\s*([0-9]{1,2})月/) {
            guard let year = Int(match.1), let month = Int(match.2) else { return nil }
            return String(format: "%04d-%02d", year, month)
        }
        return nil
    }

    static func parseJapaneseYearMonthDay(_ text: String) -> (year: Int, month: Int, day: Int)? {
        if let match = text.firstMatch(of: /令和\s*([0-9]{1,2})年\s*([0-9]{1,2})月\s*([0-9]{1,2})日/) {
            guard let era = Int(match.1), let month = Int(match.2), let day = Int(match.3) else { return nil }
            return (2018 + era, month, day)
        }
        if let match = text.firstMatch(of: /([12][0-9]{3})年\s*([0-9]{1,2})月\s*([0-9]{1,2})日/) {
            guard let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) else { return nil }
            return (year, month, day)
        }
        return nil
    }
}
