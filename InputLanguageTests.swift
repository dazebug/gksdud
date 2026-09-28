import Foundation

// The pure input-language model: registry rows, tag matching, badges per icon style, picker titles and the input menu.
func runInputLanguageTests() {
    let all = InputLanguage.all, styles = IconStyle.allCases
    featureCheck(Set(all.map(\.id)).count == all.count, "registry ids must be unique")
    for language in all {
        featureCheck(InputLanguage.match(language.id) == language, "match(\"\(language.id)\") must return its own row")
        featureCheck(language.displayName != language.id, "\(language.id) must be a tag with a CLDR name")
        featureCheck(([language.glyph] + language.modeGlyphs.values).allSatisfy { $0.count == 1 }, "\(language.id) glyphs must be single graphemes")
        featureCheck((2...3).contains(language.code.count) && language.code.allSatisfy { $0.isASCII && $0.isUppercase }, "\(language.id) code \(language.code) must be 2-3 uppercase letters")
        let titles = styles.map { $0.title(primary: language) }
        featureCheck(Set(titles).count == styles.count, "\(language.id) icon style titles \(titles) must be unique; NSPopUpButton drops a duplicate and remaps iconStyle")
    }
    featureCheck(all.last == .english && all.filter(\.isEnglish).count == 1, "English must be the last and only English row")
    featureCheck(all.filter(\.optionCharactersViaEnglish) == [.korean], "only Korean may type Option characters via English")
    let matches: [(String, InputLanguage?)] = [("ko", .korean), ("kok", nil), ("en", .english), ("en-GB", .english), ("ja", .japanese), ("ja-JP", .japanese),
        ("zh-Hant", .traditionalChinese), ("zh-TW", .traditionalChinese), ("zh_TW", .traditionalChinese), ("zh-HK", .traditionalChinese),
        ("zh-MO", .traditionalChinese), ("zh-Hant-HK", .traditionalChinese), ("yue", .cantonese), ("yue-Hant", .cantonese),
        ("yue-Hans", nil), ("zh", nil), ("zh-Hans", nil), ("ain", nil), ("und", nil), ("", nil)]
    for (tag, expected) in matches {
        let found = InputLanguage.match(tag)
        featureCheck(found == expected, "match(\"\(tag)\") is \(found?.id ?? "nil"), expected \(expected?.id ?? "nil")")
    }
    print("PASS: input language registry and matching")

    func text(_ label: String, filled: Bool, _ language: String?) -> InputBadge { .text(label, filled: filled, language: language) }
    // Today's iconLabel and sourceMenuIcon, which Korean users keep.
    let korean = [text("한", filled: true, "ko"), text("한", filled: true, "ko"), text("KO", filled: true, "ko"), .face(.hieut)]
    let english = [text("dud", filled: false, "en"), text("A", filled: false, "en"), text("EN", filled: false, "en"), .face(.d)]
    featureCheck(styles.map { $0.badge(for: .korean) } == korean, "Korean badges are \(styles.map { $0.badge(for: .korean) }), expected 한, 한, KO filled and the ㅎuㅎ face")
    featureCheck(styles.map { $0.badge(for: .english) } == english, "English badges are \(styles.map { $0.badge(for: .english) }), expected dud, A, EN outlined and the dud face")
    featureCheck(styles.map { $0.badge(for: SampleSource.twoSet) } == korean && styles.map { $0.badge(for: SampleSource.abc) } == english, "2-Set and ABC must show the Korean and English badges")
    let modes: [(InputLanguage, [String], String)] = [
        (.japanese, ["Japanese", "Japanese.Katakana", "Japanese.HalfWidthKana", "Japanese.FullWidthRoman", "Japanese.Unknown"].map { "com.apple.inputmethod." + $0 }, "あアｱＡあ"),
        (.traditionalChinese, ["Zhuyin", "ZhuyinEten", "Cangjie", "Jianyi", "Pinyin", "Shuangpin", "WBH", "Unknown"].map { "com.apple.inputmethod.TCIM." + $0 }, "注注倉速拼雙畫中"),
        (.cantonese, ["Cangjie", "Sucheng", "Phonetic", "Stroke", "Unknown"].map { "com.apple.inputmethod.TYIM." + $0 }, "倉速粵畫粵")]
    for (language, ids, glyphs) in modes {
        featureCheck(ids.count == glyphs.count, "\(language.id) mode table is uneven")
        for (mode, glyph) in zip(ids, glyphs) {
            for style in [IconStyle.glyphDud, .glyphA, .character] {
                let badge = style.badge(for: language, mode: mode)
                featureCheck(badge == text(String(glyph), filled: true, language.id), "\(style) badge for \(mode) is \(badge), expected \(glyph) filled")
            }
            featureCheck(IconStyle.code.badge(for: language, mode: mode) == text(language.code, filled: true, language.id), "code badge for \(mode) must be \(language.code) filled")
        }
        featureCheck(IconStyle.glyphDud.badge(for: language) == text(language.glyph, filled: true, language.id), "\(language.id) without a mode must show \(language.glyph)")
    }
    let sourceGlyphs = [SampleSource.hiragana, SampleSource.katakana, SampleSource.zhuyin, SampleSource.cangjie, SampleSource.cantonesePhonetic].map { IconStyle.glyphA.badge(for: $0) }
    featureCheck(sourceGlyphs == [text("あ", filled: true, "ja"), text("ア", filled: true, "ja"), text("注", filled: true, "zh-Hant"), text("倉", filled: true, "zh-Hant"), text("粵", filled: true, "yue-Hant")], "sources must show their mode glyphs, got \(sourceGlyphs)")
    let unregistered = [(SampleSource.simplifiedPinyin, "ZH"), (SampleSource.ainu, "AIN"), (SampleSource.konkani, "KOK"),
        (InputSource(id: "example.untagged", language: ""), "?"), (InputSource(id: "example.undetermined", language: "und"), "?")]
    for (source, code) in unregistered {
        let badges = styles.map { $0.badge(for: source) }
        featureCheck(badges.allSatisfy { $0 == text(code, filled: false, nil) }, "\(source.id) (\"\(source.language)\") badges are \(badges), expected an outlined \(code) in every style")
    }
    featureCheck(styles.allSatisfy { $0.badge(for: nil) == text("?", filled: false, nil) }, "no current source must show ?")
    featureCheck(["fr-CA", "english", "123"].map(InputMenu.fallbackCode) == ["FR", "ENG", "?"], "fallback codes must be at most 3 uppercase letters, or ?")
    // Text badges carry the row id as their CoreText language, so Han and kana take the input language's regional shapes.
    for language in all {
        let modes: [String?] = [nil] + language.modeGlyphs.keys.map { Optional($0) }
        for style in styles {
            for mode in modes {
                guard case let .text(_, _, tag) = style.badge(for: language, mode: mode) else { continue }
                featureCheck(tag == language.id, "\(language.id) \(style) badge is tagged \(tag ?? "nil"), expected its row id")
            }
        }
    }
    let titles: [(InputLanguage, [String])] = [(.korean, ["한 / dud", "한 / A", "KO / EN", "ㅎuㅎ / dud"]), (.japanese, ["あ / dud", "あ / A", "JA / EN", "あ / dud 캐릭터"]),
        (.traditionalChinese, ["中 / dud", "中 / A", "ZH / EN", "中 / dud 캐릭터"]), (.cantonese, ["粵 / dud", "粵 / A", "YUE / EN", "粵 / dud 캐릭터"])]
    for (language, expected) in titles {
        let found = styles.map { $0.title(primary: language) }
        featureCheck(found == expected, "\(language.id) icon style titles are \(found), expected \(expected)")
    }
    let saved = (-1...5).map(IconStyle.init(saved:))
    featureCheck(saved == [.glyphDud, .glyphDud, .glyphA, .code, .character, .glyphDud, .glyphDud] && IconStyle(saved: 7) == .glyphDud, "saved icon styles 0-3 must keep their order and others must become glyphDud, got \(saved)")
    print("PASS: badges and icon style titles")

    func menu(_ enabled: [InputSource], current: InputSource?) -> [String] {
        InputMenu.rows(enabled: enabled, current: current).map { $0.checked ? $0.title + " ✓" : $0.title }
    }
    let (abc, twoSet, hiragana, katakana) = (SampleSource.abc, SampleSource.twoSet, SampleSource.hiragana, SampleSource.katakana)
    featureCheck(menu([twoSet, abc], current: twoSet) == ["한국어 ✓", "영어"], "Korean parity: \(menu([twoSet, abc], current: twoSet))")
    featureCheck(menu([abc, twoSet], current: twoSet) == ["한국어 ✓", "영어"], "Korean must stay above English whatever order TIS returns: \(menu([abc, twoSet], current: twoSet))")
    featureCheck(InputMenu.rows(enabled: [abc, twoSet], current: nil).map(\.source) == [twoSet, abc], "each row must carry its own source")
    let japanese = menu([abc, hiragana, katakana, twoSet], current: katakana)
    featureCheck(japanese == ["한국어", "Hiragana", "Katakana ✓", "영어"], "a language with several sources must list each by name: \(japanese)")
    let kotoeri = menu([hiragana, SampleSource.kanaHiragana, katakana], current: hiragana)
    featureCheck(kotoeri == ["Hiragana (Japanese – Romaji) ✓", "Hiragana (Japanese – Kana)", "Katakana"], "same-named Kotoeri modes must add their input method: \(kotoeri)")
    let unnamedMethods = menu([InputSource(id: "example.a", language: "fr", name: "Same"), InputSource(id: "example.b", language: "fr", name: "Same")], current: nil)
    featureCheck(unnamedMethods == ["Same (example.a)", "Same (example.b)"], "same-named sources without an input method must add their ID: \(unnamedMethods)")
    featureCheck(menu([abc, SampleSource.romaji], current: SampleSource.romaji) == ["ABC", "Romaji ✓"], "several English sources must show their own names")
    let chinese = menu([abc, SampleSource.zhuyin, SampleSource.cantonesePhonetic, SampleSource.simplifiedPinyin, SampleSource.ainu], current: SampleSource.zhuyin)
    featureCheck(chinese == ["중국어(번체) ✓", "광둥어(번체)", "아이누어", "중국어(간체)", "영어"], "registered languages in registry order, then others by name, then English: \(chinese)")
    let others = menu([SampleSource.simplifiedPinyin, SampleSource.ainu, InputSource(id: "example.chinese", language: "zh", name: "Example Chinese")], current: nil)
    featureCheck(others == ["아이누어", "Pinyin – Simplified", "Example Chinese"], "other sources must group by inferred language and script: \(others)")
    featureCheck(menu([InputSource(id: "example.untagged", language: "", name: "Example"), abc], current: nil) == ["Example", "영어"], "a source without a language must show its own name")
    featureCheck(menu([twoSet, abc], current: hiragana) == ["한국어", "영어"] && menu([twoSet, abc], current: nil) == ["한국어", "영어"], "a current source that is not listed must check nothing")
    let konkani = menu([SampleSource.konkani, twoSet], current: nil)
    featureCheck(konkani == ["한국어", AppLanguage.name(of: "kok")], "Konkani (kok) must stay out of the Korean group: \(konkani)")
    var reads = 0
    func primary(_ current: InputSource?, _ enabled: [InputSource], ui: String = "ko") -> InputLanguage {
        InputMenu.primaryLanguage(current: current, enabled: { reads += 1; return enabled }, uiLanguage: ui)
    }
    featureCheck(primary(katakana, [abc, katakana]) == .japanese && reads == 0, "a registered non-English current source must be primary without reading the enabled list")
    featureCheck(primary(abc, [abc, SampleSource.zhuyin]) == .traditionalChinese, "with English current, the enabled registered language must be primary")
    featureCheck(primary(abc, [SampleSource.zhuyin, twoSet]) == .korean, "enabled languages must be taken in registry order")
    featureCheck(primary(abc, [abc], ui: "ja") == .japanese && primary(abc, [abc], ui: "zh-Hant") == .traditionalChinese, "without another enabled language, the UI language must be primary")
    featureCheck(primary(abc, [abc], ui: "ko") == .korean && primary(nil, [], ui: "en") == .korean, "Korean must be the last fallback")
    featureCheck(primary(SampleSource.ainu, [SampleSource.ainu, twoSet]) == .korean, "an unregistered current source must fall back to the enabled registered language")
    print("PASS: input menu model: grouping, order, titles, checkmarks and primary language")
}
