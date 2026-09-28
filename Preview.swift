import Foundation

// Real TIS IDs, mode IDs and English names. Tests and previews use them instead of the enabled list,
// because automation must never enable or select a real input source.
enum SampleSource {
    static let abc = InputSource(id: "com.apple.keylayout.ABC", language: "en", name: "ABC")
    static let twoSet = InputSource(id: "com.apple.inputmethod.Korean.2SetKorean", language: "ko", mode: "com.apple.inputmethod.Korean.2SetKorean", name: "2-Set Korean", methodName: "Korean")
    // Kotoeri's Romaji and Kana typing share the Hiragana mode ID and name.
    static let hiragana = InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", language: "ja", mode: "com.apple.inputmethod.Japanese", name: "Hiragana", methodName: "Japanese – Romaji")
    static let kanaHiragana = InputSource(id: "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese", language: "ja", mode: "com.apple.inputmethod.Japanese", name: "Hiragana", methodName: "Japanese – Kana")
    static let katakana = InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana", language: "ja", mode: "com.apple.inputmethod.Japanese.Katakana", name: "Katakana", methodName: "Japanese – Romaji")
    // Kotoeri's Romaji mode reports English and is ASCII-capable.
    static let romaji = InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", language: "en", mode: "com.apple.inputmethod.Roman", name: "Romaji", methodName: "Japanese – Romaji")
    static let zhuyin = InputSource(id: "com.apple.inputmethod.TCIM.Zhuyin", language: "zh-Hant", mode: "com.apple.inputmethod.TCIM.Zhuyin", name: "Zhuyin – Traditional", methodName: "Chinese, Traditional")
    static let cangjie = InputSource(id: "com.apple.inputmethod.TCIM.Cangjie", language: "zh-Hant", mode: "com.apple.inputmethod.TCIM.Cangjie", name: "Cangjie – Traditional", methodName: "Chinese, Traditional")
    static let cantonesePhonetic = InputSource(id: "com.apple.inputmethod.TYIM.Phonetic", language: "yue-Hant", mode: "com.apple.inputmethod.TYIM.Phonetic", name: "Phonetic – Cantonese", methodName: "Cantonese, Traditional")
    static let simplifiedPinyin = InputSource(id: "com.apple.inputmethod.SCIM.ITABC", language: "zh-Hans", mode: "com.apple.inputmethod.SCIM.ITABC", name: "Pinyin – Simplified", methodName: "Chinese, Simplified")
    static let ainu = InputSource(id: "com.apple.inputmethod.AinuIM.Ainu", language: "ain", mode: "com.apple.AinuIM.Ainu", name: "Ainu", methodName: "Ainu")
    static let konkani = InputSource(id: "com.apple.keylayout.Konkani", language: "kok", name: "Konkani – InScript")
}

// Stands in for InputSources.system: select only records the ID and updates current; it never calls TIS.
final class FakeInputSources {
    var current: InputSource?
    var enabled: [InputSource]
    private(set) var selected: [String] = []
    init(_ enabled: [InputSource], current: InputSource? = nil) { self.enabled = enabled; self.current = current ?? enabled.first }
    var inputSources: InputSources {
        InputSources(current: { self.current }, enabled: { self.enabled }, select: { id in
            self.selected.append(id)
            guard let source = self.enabled.first(where: { $0.id == id }) else { return false }
            self.current = source; return true
        })
    }
}
