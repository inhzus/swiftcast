enum Token: Equatable {
    case number(Double)
    /// A run of letters, as typed: a unit, a function, or a constant. The lexer doesn't
    /// know which; units are looked up later, so case is kept ("Mb" isn't "MB").
    case word(String)
    case plus, minus, times, divide, power, percent
    case open, close

    var word: String? {
        if case .word(let word) = self { word } else { nil }
    }
}

enum Lexer {
    /// Splits `text` into tokens, or returns `nil` for anything it doesn't understand.
    static func tokenize(_ text: String) -> [Token]? {
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0

        func endsWithValue() -> Bool {
            switch tokens.last {
            case .number, .word, .close, .percent: true
            default: false
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c.isASCII && (c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber)) {
                var j = i
                while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." { j += 1 }
                guard let number = Double(String(chars[i..<j])) else { return nil }
                tokens.append(.number(number))
                i = j
            } else if startsWord(c) {
                var j = i + 1
                while j < chars.count, continuesWord(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if (word == "x" || word == "X") && endsWithValue() {
                    tokens.append(.times)  // "2x3", "2 x (1+1)"
                } else {
                    tokens.append(.word(word))
                }
                i = j
            } else {
                switch c {
                case "+": tokens.append(.plus)
                case "-", "−": tokens.append(.minus)
                case "*", "×": tokens.append(.times)
                case "/", "÷": tokens.append(.divide)
                case "^": tokens.append(.power)
                case "%": tokens.append(.percent)
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                default: return nil
                }
                i += 1
            }
        }
        return tokens
    }

    /// Letters, π, and ° for "°C".
    private static func startsWord(_ c: Character) -> Bool {
        c.isLetter || c == "π" || c == "°"
    }

    /// Also ² and ³, for "m²".
    private static func continuesWord(_ c: Character) -> Bool {
        startsWord(c) || c == "²" || c == "³"
    }
}
