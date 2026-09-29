import Foundation

enum DudFace { case hieut, d
    var eye: String { self == .hieut ? "ㅎ" : "d" } // l10n-ignore: badge glyph
}

// Input languages gksdud names and badges. Adding one is a row in `all` plus a test row.
struct InputLanguage: Hashable {
    let id: String                          // BCP 47: CLDR name source and CoreText glyph language
    let languageCode: String                // compared with Locale.Language(identifier:).languageCode
    var script: String? = nil               // required inferred script; nil accepts any
    let glyph: String                       // glyph styles
    let code: String                        // code style
    // kTISPropertyInputModeID -> glyph, as in the system Input menu gksdud hides. Unlike a Dictionary, KeyValuePairs keeps this
    // order, which the screenshots' badge strip shows.
    var modeGlyphs: KeyValuePairs<String, String> = [:]
    var face: DudFace? = nil                // hand-drawn DudIcon face for the character style
    // The Option round trip switches sources around every keystroke. Kotoeri and TCIM hold multi-keystroke marked text
    // that a switch commits or discards, and their Option behaviour has never been probed.
    var optionCharactersViaEnglish = false  // only Korean composition survives the Option round trip
    static let korean = InputLanguage(id: "ko", languageCode: "ko", glyph: "한", code: "KO", face: .hieut, optionCharactersViaEnglish: true) // l10n-ignore: badge glyph
    static let japanese = InputLanguage(id: "ja", languageCode: "ja", glyph: "あ", code: "JA", modeGlyphs: [
        "com.apple.inputmethod.Japanese.Katakana": "ア", "com.apple.inputmethod.Japanese.FullWidthRoman": "Ａ",
        "com.apple.inputmethod.Japanese.HalfWidthKana": "ｱ"])
    static let traditionalChinese = InputLanguage(id: "zh-Hant", languageCode: "zh", script: "Hant", glyph: "中", code: "ZH", modeGlyphs: [
        "com.apple.inputmethod.TCIM.Zhuyin": "注", "com.apple.inputmethod.TCIM.ZhuyinEten": "注", "com.apple.inputmethod.TCIM.Cangjie": "倉",
        "com.apple.inputmethod.TCIM.Jianyi": "速", "com.apple.inputmethod.TCIM.Pinyin": "拼", "com.apple.inputmethod.TCIM.Shuangpin": "雙",
        "com.apple.inputmethod.TCIM.WBH": "畫"])
    static let cantonese = InputLanguage(id: "yue-Hant", languageCode: "yue", script: "Hant", glyph: "粵", code: "YUE", modeGlyphs: [
        "com.apple.inputmethod.TYIM.Cangjie": "倉", "com.apple.inputmethod.TYIM.Sucheng": "速",
        "com.apple.inputmethod.TYIM.Phonetic": "粵", "com.apple.inputmethod.TYIM.Stroke": "畫"])
    static let english = InputLanguage(id: "en", languageCode: "en", glyph: "A", code: "EN", face: .d)
    static let all: [InputLanguage] = [.korean, .japanese, .traditionalChinese, .cantonese, .english]  // menu order; English last

    static func match(_ tag: String) -> InputLanguage? {
        let language = Locale.Language(identifier: tag)
        guard let code = language.languageCode?.identifier else { return nil }
        return all.first { $0.languageCode == code && ($0.script == nil || $0.script == language.script?.identifier) }
    }
    var isEnglish: Bool { self == .english }
    var displayName: String { AppLanguage.name(of: id) }
    func glyph(mode: String?) -> String { mode.flatMap { id in modeGlyphs.first { $0.key == id }?.value } ?? glyph }
    // The badge strip's glyph rows: the language's own glyph, then each mode glyph once, in the order modeGlyphs lists them.
    var glyphs: [String] { modeGlyphs.reduce(into: [glyph]) { if !$0.contains($1.value) { $0.append($1.value) } } }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// Persisted as the "iconStyle" default; raw values must not change.
enum IconStyle: Int, CaseIterable {
    case glyphDud, glyphA, code, character
    init(saved value: Int) { self = IconStyle(rawValue: value) ?? .glyphDud }
    // A source without a registry row shows its uppercased language code, outlined, in every style.
    func badge(for source: InputSource?) -> InputBadge {
        guard let source else { return .text("?", filled: false, language: nil) }
        guard let language = InputLanguage.match(source.language) else { return .text(InputMenu.fallbackCode(source.language), filled: false, language: nil) }
        return badge(for: language, mode: source.mode)
    }
    // English is outlined and every other language filled; mode glyphs apply to every style but the code style.
    func badge(for language: InputLanguage, mode: String? = nil) -> InputBadge {
        if self == .character, let face = language.face { return .face(face) }
        let label = self == .code ? language.code : self == .glyphDud && language.isEnglish ? "dud" : language.glyph(mode: mode)
        return .text(label, filled: !language.isEnglish, language: language.id)
    }
    // NSPopUpButton drops a duplicate title, which would shift the saved index, so a language without a face
    // names the dud character instead of repeating "<glyph> / dud".
    func title(primary: InputLanguage) -> String {
        switch self {
        case .glyphDud: return "\(primary.glyph) / dud"
        case .glyphA: return "\(primary.glyph) / A"
        case .code: return "\(primary.code) / EN"
        case .character: return primary.face.map { "\($0.eye)u\($0.eye) / dud" }
            ?? "\(primary.glyph) / " + String(localized: "dud 캐릭터", comment: "General tab, menu bar icon picker: the character style item, after '<input language glyph> / ' for input languages without a character face of their own. dud is the English face of the gksdud character; keep it in Latin letters.")
        }
    }
}
enum InputBadge: Equatable { case text(String, filled: Bool, language: String?), face(DudFace) }

struct InputMenuRow: Equatable { let title: String; let source: InputSource; let checked: Bool }
enum InputMenu {
    // One row per enabled source: registered languages in registry order, then other languages by name, then English.
    static func rows(enabled: [InputSource], current: InputSource?, name: (String) -> String = AppLanguage.name(of:)) -> [InputMenuRow] {
        let matched = enabled.map { (source: $0, language: InputLanguage.match($0.language)) }
        func group(_ language: InputLanguage) -> (String, [InputSource]) { (name(language.id), matched.filter { $0.language == language }.map(\.source)) }
        // Other sources group by inferred language and script, so zh-Hans stays apart; a tag without a language shows the source's own name.
        var others: [(key: String, title: String, sources: [InputSource])] = []
        for (source, language) in matched where language == nil {
            let tag = Locale.Language(identifier: source.language), key = "\(tag.languageCode?.identifier ?? "")-\(tag.script?.identifier ?? "")"
            if let index = others.firstIndex(where: { $0.key == key }) { others[index].sources.append(source) }
            else { others.append((key, fallbackCode(source.language) == "?" ? source.name : name(source.language), [source])) }
        }
        let groups = InputLanguage.all.filter { !$0.isEnglish }.map(group)
            + others.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { ($0.title, $0.sources) } + [group(.english)]
        return groups.flatMap { title, sources in sources.map { source in
            // Several sources show their own names; two with one name (Kotoeri Romaji and Kana Hiragana) add their input method.
            let named = sources.filter { $0.name == source.name }.count > 1 ? "\(source.name) (\(source.methodName ?? source.id))" : source.name
            return InputMenuRow(title: sources.count == 1 ? title : named, source: source, checked: source.id == current?.id)
        } }
    }
    // The language shown next to English in the settings previews and icon-style titles.
    static func primaryLanguage(current: InputSource?, enabled: () -> [InputSource], uiLanguage: String = AppLanguage.current) -> InputLanguage {
        if let language = current.flatMap({ InputLanguage.match($0.language) }), !language.isEnglish { return language }
        let languages = enabled().compactMap { InputLanguage.match($0.language) }
        return InputLanguage.all.first { !$0.isEnglish && languages.contains($0) }
            ?? InputLanguage.match(uiLanguage).flatMap { $0.isEnglish ? nil : $0 } ?? .korean
    }
    // A badge fits three letters. Locale.Language reads "und" as a language code, but it names none.
    static func fallbackCode(_ tag: String) -> String {
        guard let code = Locale.Language(identifier: tag).languageCode?.identifier, code != "und" else { return "?" }
        let letters = String(code.filter { $0.isASCII && $0.isLetter }.prefix(3)).uppercased()
        return letters.isEmpty ? "?" : letters
    }
}
