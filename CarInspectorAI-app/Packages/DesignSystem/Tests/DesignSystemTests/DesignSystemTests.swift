import Foundation
import Testing
@testable import DesignSystem

@Suite("DesignSystem")
struct DesignSystemTests {

    @Test("金額表示: ¥カンマ区切り・符号併記（NFR-10: 色だけに依存しない）")
    func priceFormatting() {
        #expect(PriceFormatting.yen(1_830_000) == "¥1,830,000")
        #expect(PriceFormatting.signedYen(50_000) == "+¥50,000")
        #expect(PriceFormatting.signedYen(-40_000) == "−¥40,000")
    }

    @Test("VoiceOver読み上げ: 「百八十三万円」形式（03 §5: 数値の分解読み禁止）")
    func spokenPrice() {
        let spoken = PriceFormatting.spokenYen(1_830_000)
        #expect(spoken == "百八十三万円")
        #expect(PriceFormatting.spokenYen(50_000) == "五万円")
    }

    @Test("デザイントークン: スペーシング・角丸（03 §2.3）")
    func tokens() {
        #expect(CIToken.Space.xs == 4)
        #expect(CIToken.Space.m == 16)
        #expect(CIToken.Space.xl == 32)
        #expect(CIToken.Radius.card == 20)
        #expect(CIToken.Radius.button == 14)
    }
}
