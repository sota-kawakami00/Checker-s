import Foundation
import CoreGraphics
import CoreText
import Core

/// 査定書PDFレイアウトエンジン（00 §6: PDFKit + 独自レイアウト、FR-502）。
/// CoreGraphics/CoreText 直描画のため iOS / macOS 両対応（ユニットテスト可能）。
public struct AppraisalSheetRenderer: Sendable {

    public struct SheetModel: Sendable {
        public var storeName: String
        public var staffName: String
        public var issuedAt: Date
        public var vehicleLines: [(String, String)]
        public var confirmedPrice: Int
        public var tradeInReference: Int?
        public var adjustments: [(label: String, amount: Int)]
        public var basePrice: Int?
        public var marketAveragePrice: Int?
        public var repairNote: String?
        public var completenessNote: String?
        public var expiresAt: Date?

        public init(
            storeName: String,
            staffName: String,
            issuedAt: Date,
            vehicleLines: [(String, String)],
            confirmedPrice: Int,
            tradeInReference: Int?,
            adjustments: [(label: String, amount: Int)],
            basePrice: Int?,
            marketAveragePrice: Int?,
            repairNote: String?,
            completenessNote: String?,
            expiresAt: Date?
        ) {
            self.storeName = storeName
            self.staffName = staffName
            self.issuedAt = issuedAt
            self.vehicleLines = vehicleLines
            self.confirmedPrice = confirmedPrice
            self.tradeInReference = tradeInReference
            self.adjustments = adjustments
            self.basePrice = basePrice
            self.marketAveragePrice = marketAveragePrice
            self.repairNote = repairNote
            self.completenessNote = completenessNote
            self.expiresAt = expiresAt
        }
    }

    // A4 (72dpi)
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 48

    public init() {}

    /// PDF を url に書き出す
    public func render(_ model: SheetModel, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: Self.pageWidth, height: Self.pageHeight)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw AppError.storageFull
        }
        context.beginPDFPage(nil)

        var cursorY = Self.pageHeight - Self.margin

        func draw(_ text: String, size: CGFloat, bold: Bool = false, color: CGColor = CGColor(gray: 0.1, alpha: 1), indent: CGFloat = 0, lineGap: CGFloat = 8) {
            let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, "ja" as CFString)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let maxWidth = Self.pageWidth - Self.margin * 2 - indent
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: attributed.length), nil,
                CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
            )
            let frameRect = CGRect(
                x: Self.margin + indent,
                y: cursorY - suggested.height,
                width: maxWidth,
                height: suggested.height
            )
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
            CTFrameDraw(frame, context)
            cursorY -= suggested.height + lineGap
        }

        func drawDivider() {
            context.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
            context.setLineWidth(0.8)
            context.move(to: CGPoint(x: Self.margin, y: cursorY))
            context.addLine(to: CGPoint(x: Self.pageWidth - Self.margin, y: cursorY))
            context.strokePath()
            cursorY -= 14
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy年M月d日"

        // ヘッダ
        draw("車両査定書", size: 22, bold: true)
        draw("\(model.storeName)　担当: \(model.staffName)　発行日: \(dateFormatter.string(from: model.issuedAt))", size: 10, color: CGColor(gray: 0.35, alpha: 1))
        drawDivider()

        // 車両情報
        draw("車両情報", size: 13, bold: true)
        for (label, value) in model.vehicleLines {
            draw("\(label): \(value)", size: 11, indent: 8, lineGap: 4)
        }
        cursorY -= 8
        drawDivider()

        // 査定価格
        draw("査定価格", size: 13, bold: true)
        draw(Self.yen(model.confirmedPrice), size: 30, bold: true, indent: 8)
        if let tradeIn = model.tradeInReference {
            draw("下取参考価格: \(Self.yen(tradeIn))", size: 11, indent: 8)
        }
        if let expiresAt = model.expiresAt {
            draw("本査定の有効期限: \(dateFormatter.string(from: expiresAt))（発行から7日間）", size: 9, color: CGColor(gray: 0.4, alpha: 1), indent: 8)
        }
        drawDivider()

        // 内訳（FR-402: 必ず加減点の根拠付き）
        draw("査定の内訳", size: 13, bold: true)
        if let base = model.basePrice {
            draw("基準価格（市場相場）: \(Self.yen(base))", size: 11, indent: 8, lineGap: 4)
        }
        for adjustment in model.adjustments {
            let sign = adjustment.amount >= 0 ? "+" : "−"
            draw("\(sign) \(adjustment.label): \(sign)\(Self.yen(abs(adjustment.amount)))", size: 11, indent: 8, lineGap: 4)
        }
        if let market = model.marketAveragePrice {
            draw("市場平均価格: \(Self.yen(market))", size: 10, color: CGColor(gray: 0.35, alpha: 1), indent: 8, lineGap: 4)
        }
        cursorY -= 8

        if let repairNote = model.repairNote {
            drawDivider()
            draw("修復歴に関する所見", size: 13, bold: true)
            draw(repairNote, size: 10, indent: 8)
        }

        if let completenessNote = model.completenessNote {
            drawDivider()
            draw("査定時の確認状況", size: 13, bold: true)
            draw(completenessNote, size: 10, indent: 8)
        }

        drawDivider()
        draw("本査定書はAIによる解析結果をもとに担当スタッフが確認・確定したものです。価格は車両状態・市場動向により変動する場合があります。", size: 8, color: CGColor(gray: 0.45, alpha: 1))

        context.endPDFPage()
        context.closePDF()
    }

    static func yen(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return "¥\(formatter.string(from: NSNumber(value: amount)) ?? String(amount))"
    }
}
