import Foundation
import SwiftCastPluginKit

/// A name written in pinyin so it can be typed: 计算器 reads "jisuanqi", with a word start at
/// each syllable so "jsq" matches as initials. Letters and digits outside Han text are kept
/// as typed, so "QQ音乐" reads "qqyinyue".
struct PinyinReading: Hashable, Sendable {
    /// Folded, without spaces.
    let text: String
    /// Offsets into `text` where a syllable or a word begins.
    let wordStarts: [Int]
    /// For each Character of `text`, the offset of the Character in the original name it
    /// came from, so a match can be highlighted on the name itself.
    let sources: [Int]
}

extension FuzzyMatcher.Candidate {
    init(_ reading: PinyinReading) {
        self.init(folded: Array(reading.text), wordStarts: reading.wordStarts, sources: reading.sources)
    }
}

enum Pinyin {
    /// Which Chinese a name is written in, or `nil` when it shouldn't get pinyin.
    enum Variant: Equatable {
        case simplified
        case traditional
    }

    /// How to read `name`. `language` is the localization the name came from, which the app
    /// itself declares and so decides; without one the script decides: kana means Japanese
    /// (no pinyin, since kanji read as Mandarin are wrong words), and Han text is Chinese.
    static func variant(of name: String, language: String?) -> Variant? {
        if let language {
            let parsed = Locale.Language(identifier: language)
            guard parsed.languageCode == .chinese else { return nil }
            switch parsed.script?.identifier {
            case "Hant": return .traditional
            case "Hans": return .simplified
            default:
                let traditionalRegions: Set<String> = ["TW", "HK", "MO"]
                return parsed.region.map { traditionalRegions.contains($0.identifier) } == true ? .traditional : .simplified
            }
        }
        let scalars = name.unicodeScalars
        guard name.contains(where: isHan) else { return nil }
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) }) {
            return nil
        }
        let best = CFStringTokenizerCopyBestStringLanguage(name as CFString, CFRangeMake(0, (name as NSString).length)) as String?
        return best == "zh-Hant" ? .traditional : .simplified
    }

    /// Readings of `name` in pinyin, empty when it has no Han characters or isn't Chinese
    /// (see `variant(of:language:)`).
    ///
    /// The first reads words with `CFStringTokenizer`, which reads polyphones in context (音乐
    /// is "yinyue", 银行 is "yinhang"). The second reads character by character and is kept
    /// when it differs, so a word the tokenizer misreads can still be found. Traditional
    /// characters are read as their simplified forms, which the tokenizer knows.
    static func readings(of name: String, language: String? = nil) -> [PinyinReading] {
        // Format characters (BOM, bidi and zero-width marks) can end tokenizing early and would
        // throw off the character count a word's reading is split by.
        var cleaned: [Character] = []
        var sources: [Int] = []
        for (index, character) in name.enumerated() {
            let scalars = character.unicodeScalars.filter { $0.properties.generalCategory != .format }
            guard !scalars.isEmpty else { continue }
            cleaned.append(Character(String(String.UnicodeScalarView(scalars))))
            sources.append(index)
        }
        guard let variant = variant(of: String(cleaned), language: language) else { return [] }
        if variant == .traditional,
           let simplified = String(cleaned).applyingTransform(StringTransform("Hant-Hans"), reverse: false).map({ Array($0) }),
           simplified.count == cleaned.count {
            cleaned = simplified
        }

        var result: [PinyinReading] = []
        for perCharacter in [false, true] {
            if let reading = reading(of: cleaned, sources: sources, perCharacter: perCharacter),
               !result.contains(where: { $0.text == reading.text }) {
                result.append(reading)
            }
        }
        return result
    }

    private static func reading(of cleaned: [Character], sources cleanedSources: [Int], perCharacter: Bool) -> PinyinReading? {
        guard cleaned.contains(where: isHan) else { return nil }
        var builder = Builder()
        for segment in segments(of: cleaned) {
            let characters = Array(cleaned[segment.range])
            let sources = Array(cleanedSources[segment.range])
            if characters.allSatisfy(isHan) {
                let syllables = (perCharacter ? nil : segment.transcription)
                    .flatMap { split(letters(of: $0), into: characters.count) }
                    ?? characters.map { letters(of: String($0).applyingTransform(.mandarinToLatin, reverse: false) ?? "") }
                for (syllable, source) in zip(syllables, sources) {
                    builder.append(syllable, from: source)
                }
            } else {
                let starts = Set(FuzzyMatcher.wordStarts(characters))
                for (offset, character) in characters.enumerated() {
                    if isHan(character) {
                        let reading = String(character).applyingTransform(.mandarinToLatin, reverse: false) ?? ""
                        builder.append(letters(of: reading), from: sources[offset])
                    } else if character.isLetter || character.isNumber {
                        builder.append(String(FuzzyMatcher.fold(character)), from: sources[offset],
                                       startsWord: starts.contains(offset))
                    }
                }
            }
        }
        guard !builder.text.isEmpty else { return nil }
        return PinyinReading(text: builder.text, wordStarts: builder.wordStarts, sources: builder.sources)
    }

    /// Splits a toneless reading into exactly `count` syllables, one per character, or `nil`
    /// when it can't be. The count settles what pinyin alone can't: "xian" is 西安 (xi + an)
    /// in two characters and 先 in one.
    static func split(_ reading: String, into count: Int) -> [String]? {
        let letters = Array(reading)
        guard count > 0, letters.count >= count else { return nil }
        var deadEnds = Set<[Int]>()
        var parts: [String] = []

        func fill(from start: Int, remaining: Int) -> Bool {
            if remaining == 0 { return start == letters.count }
            if deadEnds.contains([start, remaining]) { return false }
            // Longer syllables first: "pingan" is ping + an.
            let longest = min(maxSyllableLength, letters.count - start)
            for length in stride(from: longest, through: 1, by: -1) {
                let syllable = String(letters[start..<(start + length)])
                guard syllables.contains(syllable) else { continue }
                parts.append(syllable)
                if fill(from: start + length, remaining: remaining - 1) { return true }
                parts.removeLast()
            }
            deadEnds.insert([start, remaining])
            return false
        }
        return fill(from: 0, remaining: count) ? parts : nil
    }

    // MARK: - Helpers

    private struct Builder {
        var text = ""
        var wordStarts: [Int] = []
        var sources: [Int] = []

        mutating func append(_ part: String, from source: Int, startsWord: Bool = true) {
            guard !part.isEmpty else { return }
            if startsWord { wordStarts.append(text.count) }
            text += part
            sources += Array(repeating: source, count: part.count)
        }
    }

    private struct Segment {
        let range: Range<Int>
        let transcription: String?
    }

    /// `characters` cut into the tokenizer's words, with the stretches between words (spaces,
    /// punctuation) as segments of their own, so every character lands in exactly one.
    private static func segments(of characters: [Character]) -> [Segment] {
        let string = String(characters)
        // UTF-16 offset where each character starts, to turn token ranges into character ranges.
        var utf16Starts: [Int: Int] = [:]
        var offset = 0
        for (index, character) in characters.enumerated() {
            utf16Starts[offset] = index
            offset += character.utf16.count
        }
        utf16Starts[offset] = characters.count

        var result: [Segment] = []
        var position = 0
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, string as CFString, CFRangeMake(0, offset),
            kCFStringTokenizerUnitWord, Locale(identifier: "zh_Hans") as CFLocale)
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let lower = utf16Starts[range.location],
                  let upper = utf16Starts[range.location + range.length],
                  lower >= position, lower < upper
            else { continue }
            if position < lower { result.append(Segment(range: position..<lower, transcription: nil)) }
            let transcription = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            result.append(Segment(range: lower..<upper, transcription: transcription))
            position = upper
        }
        if position < characters.count {
            result.append(Segment(range: position..<characters.count, transcription: nil))
        }
        return result
    }

    /// The ASCII letters of a transcription with tones removed: "lv̀sè" → "lvse".
    private static func letters(of transcription: String) -> String {
        transcription.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isASCII && $0.isLetter }
    }

    static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isUnifiedIdeograph
                || scalar.value == 0x3007                      // 〇
                || (0xF900...0xFAFF).contains(scalar.value)    // CJK compatibility ideographs
                || (0x2F800...0x2FA1F).contains(scalar.value)  // ... and their supplement
        }
    }

    /// Mandarin syllables, toneless, with ü written as v. Interjections such as "m", "n" and
    /// "ng" are left out: they never appear inside a word, and would let "xian" split as
    /// xia + n.
    private static let syllables: Set<String> = {
        let rows = [
            "a ai an ang ao",
            "ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu",
            "ca cai can cang cao ce cen ceng ci cong cou cu cuan cui cun cuo",
            "cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo",
            "da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo",
            "e ei en eng er",
            "fa fan fang fei fen feng fiao fo fou fu",
            "ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo",
            "ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo",
            "ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun",
            "ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo",
            "la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lue lun luo lv lve",
            "ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu",
            "na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nue nun nuo nv nve",
            "o ou",
            "pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu",
            "qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun",
            "ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo",
            "sa sai san sang sao se sen seng si song sou su suan sui sun suo",
            "sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo",
            "ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo",
            "wa wai wan wang wei wen weng wo wu",
            "xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun",
            "ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun",
            "za zai zan zang zao ze zei zen zeng zi zong zou zu zuan zui zun zuo",
            "zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo",
        ]
        return Set(rows.flatMap { $0.split(separator: " ").map(String.init) })
    }()

    private static let maxSyllableLength = syllables.map(\.count).max() ?? 6
}
