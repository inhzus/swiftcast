import Foundation
import Testing
@testable import AppsPlugin

struct PinyinTests {
    @Test func readsEachCharacterAsASyllable() throws {
        let reading = try #require(Pinyin.reading(of: "计算器"))
        #expect(reading.text == "jisuanqi")
        #expect(reading.wordStarts == [0, 2, 6])
        #expect(reading.sources == [0, 0, 1, 1, 1, 1, 2, 2])
    }

    @Test func readsPolyphonesInContext() {
        #expect(Pinyin.reading(of: "音乐")?.text == "yinyue")
        #expect(Pinyin.reading(of: "银行")?.text == "yinhang")
        #expect(Pinyin.reading(of: "地图")?.text == "ditu")
    }

    @Test func keepsOtherTextAsTyped() throws {
        let reading = try #require(Pinyin.reading(of: "Safari浏览器"))
        #expect(reading.text == "safariliulanqi")
        #expect(reading.sources.last == 8)
        #expect(Pinyin.reading(of: "QQ音乐")?.text == "qqyinyue")
        #expect(Pinyin.reading(of: "AirPort 实用工具")?.wordStarts.count == 6)
    }

    @Test func skipsNamesWithoutHan() {
        #expect(Pinyin.reading(of: "Safari") == nil)
        #expect(Pinyin.reading(of: "") == nil)
    }

    @Test func ignoresFormatCharacters() {
        #expect(Pinyin.reading(of: "\u{FEFF}微信\u{200B}")?.text == "weixin")
    }

    @Test func splitsByCharacterCount() {
        #expect(Pinyin.split("xian", into: 2) == ["xi", "an"])
        #expect(Pinyin.split("xian", into: 1) == ["xian"])
        #expect(Pinyin.split("pingan", into: 2) == ["ping", "an"])
        #expect(Pinyin.split("lvse", into: 2) == ["lv", "se"])
        #expect(Pinyin.split("qqq", into: 1) == nil)
    }
}
