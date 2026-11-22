import Foundation
import Testing
@testable import AppsPlugin

struct PinyinTests {
    @Test func readsEachCharacterAsASyllable() throws {
        let reading = try #require(Pinyin.readings(of: "计算器").first)
        #expect(reading.text == "jisuanqi")
        #expect(reading.wordStarts == [0, 2, 6])
        #expect(reading.sources == [0, 0, 1, 1, 1, 1, 2, 2])
    }

    @Test func readsPolyphonesInContext() {
        #expect(Pinyin.readings(of: "音乐").first?.text == "yinyue")
        #expect(Pinyin.readings(of: "银行").first?.text == "yinhang")
        #expect(Pinyin.readings(of: "地图").first?.text == "ditu")
    }

    @Test func keepsOtherTextAsTyped() throws {
        let reading = try #require(Pinyin.readings(of: "Safari浏览器").first)
        #expect(reading.text == "safariliulanqi")
        #expect(reading.sources.last == 8)
        #expect(Pinyin.readings(of: "QQ音乐").first?.text == "qqyinyue")
        #expect(Pinyin.readings(of: "AirPort 实用工具").first?.wordStarts.count == 6)
    }

    @Test func skipsNamesWithoutHan() {
        #expect(Pinyin.readings(of: "Safari").isEmpty)
        #expect(Pinyin.readings(of: "").isEmpty)
    }

    @Test func ignoresFormatCharacters() {
        #expect(Pinyin.readings(of: "\u{FEFF}微信\u{200B}").first?.text == "weixin")
    }

    @Test func splitsByCharacterCount() {
        #expect(Pinyin.split("xian", into: 2) == ["xi", "an"])
        #expect(Pinyin.split("xian", into: 1) == ["xian"])
        #expect(Pinyin.split("pingan", into: 2) == ["ping", "an"])
        #expect(Pinyin.split("lvse", into: 2) == ["lv", "se"])
        #expect(Pinyin.split("qqq", into: 1) == nil)
    }

    @Test func choosesTheVariantFromTheTranslationsLanguage() {
        #expect(Pinyin.variant(of: "计算器", language: "zh_CN") == .simplified)
        #expect(Pinyin.variant(of: "计算器", language: "zh-Hans") == .simplified)
        #expect(Pinyin.variant(of: "計算機", language: "zh_TW") == .traditional)
        #expect(Pinyin.variant(of: "計算機", language: "zh-Hant") == .traditional)
        #expect(Pinyin.variant(of: "計算機", language: "zh_HK") == .traditional)
        #expect(Pinyin.variant(of: "計算機", language: "ja") == nil)
    }

    @Test func choosesTheVariantFromTheScriptWithoutALanguage() {
        #expect(Pinyin.variant(of: "音乐", language: nil) == .simplified)
        #expect(Pinyin.variant(of: "音樂", language: nil) == .traditional)
        #expect(Pinyin.variant(of: "システム設定", language: nil) == nil)
        #expect(Pinyin.variant(of: "Safari", language: nil) == nil)
    }

    @Test func readsTraditionalNamesAsSimplified() throws {
        let readings = Pinyin.readings(of: "音樂", language: "zh_TW")
        let reading = try #require(readings.first)
        #expect(reading.text == "yinyue")
        #expect(Set(reading.sources) == [0, 1])
    }

    @Test func skipsJapaneseNames() {
        #expect(Pinyin.readings(of: "計算機", language: "ja").isEmpty)
        #expect(Pinyin.readings(of: "システム設定").isEmpty)
    }

    @Test func keepsTheCharacterByCharacterReadingWhenItDiffers() {
        #expect(Pinyin.readings(of: "音乐").map(\.text) == ["yinyue", "yinle"])
        #expect(Pinyin.readings(of: "计算器").map(\.text) == ["jisuanqi"])
    }
}
