import AppKit
import ServiceManagement

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
    // The Korean and English badges from before the registry, which Korean users keep.
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

// AppDelegate on fake input sources and faked trust. Nothing here may reach the live input sources, Caps Lock, login item or event taps.
func runInputWiringTests() {
    let suiteName = "io.gksdud.wiring-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let refused = NSError(domain: "wiring-test", code: 1)
    let fake = FakeInputSources([SampleSource.romaji, SampleSource.hiragana, SampleSource.katakana, SampleSource.abc])
    var trusted = false, capsWrites: [Bool] = [], loginWrites: [Bool] = []
    let environment = AppDelegate.Environment(inputSources: fake.inputSources, accessibilityTrusted: { trusted },
        capsLock: { capsWrites.append($0); throw refused }, loginItemStatus: { .notRegistered }, setLoginItem: { loginWrites.append($0); throw refused })
    let shortcuts = ShortcutPreferences(read: { [:] }, write: { _ in throw refused }, activate: { throw refused })
    let delegate = AppDelegate(engine: Engine(defaults: defaults, discover: { [] }, shortcutPreferences: shortcuts), environment: environment)
    featureCheck(delegate.currentIsEnglish, "Kotoeri's Romaji mode reports en, so it must count as English")
    // Tags as TIS reports them; el and es start with e but are not English.
    for other in [SampleSource.hiragana, InputSource(id: "com.apple.keylayout.Greek", language: "el"), InputSource(id: "com.apple.keylayout.Spanish", language: "es")] {
        fake.current = other
        featureCheck(!delegate.currentIsEnglish, "\(other.id) (\(other.language)) must not count as English")
    }
    fake.current = nil
    featureCheck(!delegate.currentIsEnglish, "no current source must not count as English")
    func failure(_ name: String) -> String { "영어 전환을 확인하지 못해 대문자 전환을 취소했습니다. 영어와 \(name) 입력 소스를 최근 입력 소스로 선택해주세요." }
    let untagged = InputSource(id: "example.untagged", language: "", name: "Example")
    for (source, name) in [(SampleSource.hiragana, "일본어"), (SampleSource.twoSet, "한국어"), (SampleSource.ainu, "아이누어"), (untagged, "Example")] {
        let message = delegate.longPressFailureMessage(for: source)
        featureCheck(message == failure(name), "long-press failure for \(source.id) is \"\(message)\", expected the name \(name)")
    }
    defaults.set(true, forKey: "active"); defaults.set(true, forKey: "switchOnKeyDown")
    let denied = SystemAccess.denied.count
    delegate.ensureKeyTap()
    featureCheck(delegate.keyTap == nil && SystemAccess.denied.count == denied && !delegate.pressSwitch.isEnabled && !delegate.capsPreservationActive,
        "without faked trust, ensureKeyTap must stop before the event tap")
    trusted = true
    delegate.ensureKeyTap()
    featureCheck(delegate.keyTap == nil && SystemAccess.denied.count == denied + 1 && SystemAccess.denied.last == "event tap" && delegate.pressSwitch.isEnabled && delegate.capsPreservationActive,
        "with trust faked true, the latch must refuse the event tap; denied \(SystemAccess.denied.suffix(2))")
    featureCheck(capsWrites.isEmpty && loginWrites.isEmpty && fake.selected.isEmpty, "the wiring checks must not change Caps Lock, the login item or the input source")
    let katakana = SampleSource.katakana
    featureCheck(fake.inputSources.select(katakana.id) && fake.selected == [katakana.id] && fake.current == katakana, "FakeInputSources.select must record the ID and make its source current")
    featureCheck(!fake.inputSources.select("example.missing") && fake.selected == [katakana.id, "example.missing"] && fake.current == katakana, "an unknown ID must be recorded, fail and keep the current source")
    // Input method IDs as on this Mac, plus a shorter prefix that must lose to the longest one.
    let methods = [InputSource(id: "com.apple.inputmethod", language: "", name: "Shorter prefix"), InputSource(id: "com.apple.inputmethod.Korean", language: "ko", name: "Korean"),
        InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping", language: "ja", name: "Japanese – Romaji"), InputSource(id: "com.apple.inputmethod.Kotoeri.KanaTyping", language: "ja", name: "Japanese – Kana"),
        InputSource(id: "com.apple.inputmethod.TCIM", language: "zh-Hant", name: "Chinese, Traditional"), InputSource(id: "com.apple.inputmethod.TYIM", language: "yue-Hant", name: "Cantonese, Traditional"),
        InputSource(id: "com.apple.inputmethod.SCIM", language: "zh-Hans", name: "Chinese, Simplified"), InputSource(id: "com.apple.inputmethod.Ainu", language: "ain", name: "Ainu")]
    for source in [SampleSource.abc, SampleSource.twoSet, SampleSource.hiragana, SampleSource.kanaHiragana, SampleSource.katakana, SampleSource.romaji, SampleSource.zhuyin,
                   SampleSource.cangjie, SampleSource.cantonesePhonetic, SampleSource.simplifiedPinyin, SampleSource.ainu, SampleSource.konkani] {
        let name = InputSources.methodName(of: source.id, among: methods)
        featureCheck(name == source.methodName, "\(source.id) input method is \(name ?? "nil"), expected \(source.methodName ?? "nil")")
    }
    // Read-only lookups; installed(id:) also finds the modes of disabled input methods, which only previews may name.
    if let abc = InputSources.source(id: SampleSource.abc.id).flatMap(InputSources.read) {
        let installed = InputSources.installed(id: katakana.id)
        featureCheck(InputSources.installed(id: abc.id) == abc && installed?.language == "ja" && installed?.mode == katakana.mode && installed?.name.isEmpty == false,
            "installed(id:) must read ABC as source(id:) does and find Kotoeri Katakana, got \(String(describing: installed))")
        featureCheck(InputSources.installed(id: "io.gksdud.nonexistent-input-source") == nil, "an unknown ID must not be installed")
    } else { print("SKIP: installed input source lookups (ABC input source is unavailable)") }
    print("PASS: environment wiring: English detection, long-press failure names, trust and the event tap latch, fake selection, input method names, installed lookups")
    runStatusMenuWiringTests()
}

// Part 2: the status menu, indicator and previews on PreviewFixture, which never creates a status item.
func runStatusMenuWiringTests() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    var fixtures: [PreviewFixture] = []
    func fixture(_ language: String, _ state: PreviewState = PreviewState(), resolveNames: Bool = false) -> PreviewFixture {
        do { let made = try PreviewFixture(uiLanguage: language, state: state, resolveNames: resolveNames); fixtures.append(made); return made }
        catch { fputs("FAIL: preview fixture for \(language): \(error)\n", stderr); exit(1) }
    }
    func entry(_ menu: NSMenu, _ title: String) -> NSMenuItem? { menu.items.first { $0.title == title } }
    func rows(_ fixture: PreviewFixture) -> [NSMenuItem] { fixture.delegate.statusMenu.items.filter { $0.action == #selector(AppDelegate.selectInputSource(_:)) } }
    func titles(_ items: [NSMenuItem]) -> [String] { items.map { $0.state == .on ? $0.title + " ✓" : $0.title } }
    // Drawn at 2x, where a mode glyph or a regional Han shape shows in the pixels.
    func pixels(_ image: NSImage?) -> Data? {
        guard let image, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width) * 2, pixelsHigh: Int(image.size.height) * 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let data = bitmap.bitmapData else { return nil }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size)); NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    func badge(_ label: String, filled: Bool, _ language: String?) -> Data? { pixels(AppDelegate.badgeImage(label: label, filled: filled, language: language)) }
    // Font, glyph and position of every glyph; a tag may split a run without changing what is drawn.
    func layout(_ text: NSAttributedString) -> [String] {
        (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as? [CTRun] ?? []).flatMap { run -> [String] in
            let count = CTRunGetGlyphCount(run), font = CTFontCopyPostScriptName((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs); CTRunGetPositions(run, CFRange(), &positions)
            return zip(glyphs, positions).map { "\(font) \($0) \($1.x)" }
        }
    }

    // A characterization of today's menu for the common Korean setup: one Korean and one English source.
    let korean = fixture("ko"), menu = korean.delegate.statusMenu
    let visible = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
    featureCheck(visible == ["gksdud", "한국어", "영어", "활성화", "누를 때 전환", "로그인 시 시작", "메뉴바에 표시", "설정..", "종료"], "Korean status menu is \(visible)")
    featureCheck(menu.items[1].action == #selector(AppDelegate.showAbout) && menu.items[1].isHidden, "the update entry must stay at index 1, hidden without an update")
    let keys = menu.items.filter { !$0.keyEquivalent.isEmpty }.map { "\($0.title) \($0.keyEquivalent)" }
    featureCheck(keys == ["설정.. ,", "종료 q"], "status menu key equivalents are \(keys)")
    featureCheck(entry(menu, "한국어")?.state == .on && entry(menu, "영어")?.state == .off, "한국어 must be checked and 영어 not")
    featureCheck(entry(menu, "한국어")?.image != nil && entry(menu, "영어")?.image != nil, "the input rows must show badges")
    featureCheck(pixels(entry(menu, "한국어")?.image) == badge("한", filled: true, "ko") && pixels(entry(menu, "영어")?.image) == badge("dud", filled: false, "en"), "the rows must show today's 한 and dud badges")
    print("PASS: status menu Korean parity: titles, hidden update entry, key equivalents, checkmark and row badges")

    // One row per source. A language with several sources lists them by the system's names; the check, badge and selection follow the source.
    let japanese = fixture("ja"), (hiragana, katakana, abc) = (SampleSource.hiragana, SampleSource.katakana, SampleSource.abc)
    featureCheck(titles(rows(japanese)) == ["Hiragana ✓", "Katakana", "영어"], "Japanese scene rows are \(titles(rows(japanese)))")
    featureCheck(rows(japanese).map { $0.representedObject as? String } == [hiragana.id, katakana.id, abc.id], "each row must carry its source ID")
    japanese.inputs.current = katakana
    japanese.delegate.updateInputIndicator()
    featureCheck(titles(rows(japanese)) == ["Hiragana", "Katakana ✓", "영어"], "the check must follow the current source: \(titles(rows(japanese)))")
    featureCheck(japanese.delegate.inputBadge.accessibilityLabel() == "현재 입력: 일본어", "the indicator is labelled \(japanese.delegate.inputBadge.accessibilityLabel() ?? "nil")")
    featureCheck(pixels(japanese.delegate.inputBadge.image) == badge("ア", filled: true, "ja") && badge("ア", filled: true, "ja") != badge("あ", filled: true, "ja"), "the indicator must show ア for Katakana")
    japanese.inputs.current = hiragana
    japanese.delegate.updateInputIndicator()
    japanese.delegate.statusMenu.performActionForItem(at: japanese.delegate.statusMenu.index(of: rows(japanese)[1]))
    featureCheck(japanese.inputs.selected == [katakana.id] && japanese.inputs.current == katakana && titles(rows(japanese)) == ["Hiragana", "Katakana ✓", "영어"],
        "choosing the Katakana row must select exactly that source; selected \(japanese.inputs.selected)")
    japanese.inputs.enabled = [hiragana, SampleSource.kanaHiragana, katakana, abc]
    japanese.delegate.menuNeedsUpdate(japanese.delegate.statusMenu)
    featureCheck(titles(rows(japanese)) == ["Hiragana (Japanese – Romaji)", "Hiragana (Japanese – Kana)", "Katakana ✓", "영어"], "Romaji and Kana Hiragana must add their input method: \(titles(rows(japanese)))")
    let chinese = fixture("zh-Hant")
    chinese.inputs.enabled += [SampleSource.cantonesePhonetic, SampleSource.simplifiedPinyin, SampleSource.ainu, SampleSource.konkani]
    chinese.delegate.menuNeedsUpdate(chinese.delegate.statusMenu)
    let chineseRows = rows(chinese)
    featureCheck(titles(chineseRows) == ["Zhuyin – Traditional ✓", "Cangjie – Traditional", "광둥어(번체)", "아이누어", "중국어(간체)", AppLanguage.name(of: "kok"), "영어"], "Chinese rows are \(titles(chineseRows))")
    let chineseBadges = [badge("注", filled: true, "zh-Hant"), badge("倉", filled: true, "zh-Hant"), badge("粵", filled: true, "yue-Hant"), badge("AIN", filled: false, nil),
        badge("ZH", filled: false, nil), badge("KOK", filled: false, nil), badge("dud", filled: false, "en")]
    featureCheck(chineseRows.map { pixels($0.image) } == chineseBadges && Set(chineseBadges.map { $0 ?? Data() }).count == chineseBadges.count, "rows must show their sources' method glyphs and outlined codes")
    print("PASS: input rows for Japanese, Traditional Chinese, Cantonese and unregistered sources: names, checkmarks, badges, indicator and selection")

    // The previews and icon style titles put the primary input language next to English. Only the glyph before " / " carries its CoreText language.
    let koreanPicker = korean.delegate.iconPicker
    featureCheck(koreanPicker.itemTitles == ["한 / dud", "한 / A", "KO / EN", "ㅎuㅎ / dud"], "Korean icon style titles are \(koreanPicker.itemTitles)")
    featureCheck(koreanPicker.itemArray.allSatisfy { layout($0.attributedTitle ?? NSAttributedString()) == layout(NSAttributedString(string: $0.title, attributes: [.font: koreanPicker.font!])) },
        "the ko tag must not change how the Korean icon style titles are drawn")
    featureCheck(korean.delegate.languagePreview.accessibilityLabel() == "한국어 아이콘 미리보기" && korean.delegate.englishPreview.accessibilityLabel() == "영어 아이콘 미리보기", "Korean preview labels must not change")
    // A saved style other than the first shows that the titles change in place instead of being added again.
    let mixed = fixture("ko"), picker = mixed.delegate.iconPicker
    picker.selectItem(at: IconStyle.character.rawValue); _ = picker.sendAction(picker.action, to: picker.target)
    mixed.inputs.enabled = [abc, SampleSource.zhuyin]; mixed.inputs.current = abc
    mixed.delegate.refreshIconPreviews()
    featureCheck(picker.itemTitles == ["中 / dud", "中 / A", "ZH / EN", "中 / dud 캐릭터"] && picker.indexOfSelectedItem == IconStyle.character.rawValue, "icon style titles are \(picker.itemTitles), selected \(picker.indexOfSelectedItem)")
    featureCheck(mixed.delegate.languagePreview.accessibilityLabel() == "중국어(번체) 아이콘 미리보기" && mixed.delegate.englishPreview.accessibilityLabel() == "영어 아이콘 미리보기",
        "preview labels are \(mixed.delegate.languagePreview.accessibilityLabel() ?? "nil") and \(mixed.delegate.englishPreview.accessibilityLabel() ?? "nil")")
    featureCheck(pixels(mixed.delegate.languagePreview.image) == badge("中", filled: true, "zh-Hant") && pixels(mixed.delegate.englishPreview.image) == pixels(DudIcon.badge(korean: false)),
        "the character style previews must show 中, which has no face, and the dud face")
    for index in 0..<picker.numberOfItems {
        guard let title = picker.item(at: index)?.attributedTitle else { featureCheck(false, "icon style item \(index) has no attributed title"); continue }
        var tagged: [NSRange] = []
        title.enumerateAttribute(.coreTextLanguage, in: NSRange(location: 0, length: title.length)) { value, range, _ in if value != nil { tagged.append(range) } }
        let glyph = (title.string as NSString).range(of: " / ").location, language = title.attribute(.coreTextLanguage, at: 0, effectiveRange: nil) as? String
        featureCheck(tagged == [NSRange(location: 0, length: glyph)] && language == "zh-Hant" && title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == picker.font,
            "icon style item \(title.string) must tag only its glyph with zh-Hant in the picker font, tagged \(tagged)")
    }
    let characterTitle = glyphRunFonts(picker.item(at: IconStyle.character.rawValue)?.attributedTitle ?? NSAttributedString())
    featureCheck(characterTitle.first?.contains("PingFangUITextTC") == true && characterTitle.last?.contains("AppleSDGothicNeo") == true, "中 / dud 캐릭터 must draw 中 in PingFang TC and the UI text in the UI font: \(characterTitle)")
    print("PASS: previews and icon style titles follow the input language: titles in place, labels, badges, glyph-only CoreText language")

    // Rows are rebuilt on open, so they follow the icon style without patching items; the indicator and previews change at once.
    let styles = korean.delegate.iconPicker
    styles.selectItem(at: IconStyle.code.rawValue)
    featureCheck(styles.sendAction(styles.action, to: styles.target) && korean.defaults.integer(forKey: "iconStyle") == IconStyle.code.rawValue, "choosing the code style must save it")
    korean.delegate.menuNeedsUpdate(korean.delegate.statusMenu)
    let (ko, en) = (badge("KO", filled: true, "ko"), badge("EN", filled: false, "en"))
    featureCheck(rows(korean).map { pixels($0.image) } == [ko, en] && pixels(korean.delegate.inputBadge.image) == ko && pixels(korean.delegate.tabButtons.first?.image) == ko,
        "the code style must show KO and EN in the rows and KO in the indicator")
    featureCheck(pixels(korean.delegate.languagePreview.image) == ko && pixels(korean.delegate.englishPreview.image) == en, "the code style previews must show KO and EN")

    // Korean users keep today's pixels: the ko and en tags draw exactly what untagged text drew.
    for (label, filled, language) in [("한", true, "ko"), ("KO", true, "ko"), ("dud", false, "en"), ("A", false, "en"), ("EN", false, "en")] {
        featureCheck(badge(label, filled: filled, language) == badge(label, filled: filled, nil), "the \(label) badge must draw the same pixels with the \(language) tag")
    }
    featureCheck(badge("中", filled: true, "zh-Hant") != badge("中", filled: true, "ja"), "a Han badge must take its input language's regional shape")
    print("PASS: Korean badge pixels unchanged: 한, KO, dud, A and EN draw the same with their language tags, and 中 follows its tag")

    // Every label a badge draws, laid out with the badge's own attributes, must come from its input language's Apple standard font whatever the UI language.
    let standardFonts = ["ko": "AppleSDGothicNeo", "ja": "HiraKakuInterface", "zh-Hant": "PingFangUITextTC", "yue-Hant": "PingFangUITextHK", "en": nil]
    for language in InputLanguage.all {
        featureCheck(standardFonts.keys.contains(language.id), "\(language.id) needs a standard font row")
        let modes = [nil] + language.modeGlyphs.keys.sorted().map { Optional($0) }
        let labels = Set(modes.flatMap { mode in IconStyle.allCases.compactMap { style -> String? in
            if case let .text(label, _, _) = style.badge(for: language, mode: mode) { return label }; return nil } })
        for label in labels.sorted() {
            let text = AppDelegate.badgeText(label, language: language.id), fonts = glyphRunFonts(text)
            // Latin letters must stay in the badge's own font; everything else needs the language's standard font.
            let own = (text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { CTFontCopyPostScriptName($0 as CTFont) as String }
            let expected = label.unicodeScalars.allSatisfy(\.isASCII) ? own : standardFonts[language.id] ?? nil
            featureCheck(expected != nil && !fonts.isEmpty && fonts.allSatisfy { $0.contains(expected!) }, "\(language.id) badge \(label) is drawn in \(fonts), expected \(expected ?? "a standard font")")
        }
    }
    print("PASS: badge glyphs use their input language's Apple standard font: Apple SD Gothic Neo, Hiragino, PingFang TC and PingFang HK under a Korean UI")

    // The walk and screenshots show the names the system gives the sources in the UI language, read without enabling anything.
    let named = fixture("ja", resolveNames: true), installed = [hiragana, katakana].map { InputSources.installed(id: $0.id)?.name ?? $0.name }
    featureCheck(titles(rows(named)) == [installed[0] + " ✓", installed[1], "영어"], "resolved Japanese rows are \(titles(rows(named))), expected the installed names \(installed)")
    let attention = fixture("ko", PreviewState(trusted: false, updateAvailable: true, keyboardWarning: true, longPressFailure: true))
    featureCheck(!attention.delegate.statusMenu.items[1].isHidden && !attention.delegate.keyboardWarningRow.isHidden && !attention.delegate.pressSwitch.isEnabled
        && attention.delegate.longPressSwitch.toolTip == attention.delegate.longPressFailureMessage(for: SampleSource.twoSet), "the attention state must show the update, the keyboard warning, missing trust and the long-press failure")
    for made in fixtures {
        let problems = made.verifyUntouched()
        featureCheck(problems.isEmpty, "the preview fixture reached the live system: \(problems)")
        made.close()
    }
    print("PASS: preview fixture untouched: no event tap, no blocked or recorded system change, no undo keys, same Input menu and shortcut, in the default and attention states")
}
