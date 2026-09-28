import AppKit

func runLocalizationTests() {
    featureCheck(AppLanguage.resolve(localizations: [], preferred: ["en"]) == "ko", "a bundle without localizations, like the bare binary, must resolve to ko")
    featureCheck(AppLanguage.resolve(localizations: ["ko", "ja", "zh-Hant"], preferred: ["ja", "ja"]) == "ja", "the bundle's first preferred localization must win")
    featureCheck(["ko", "en", "ja", "zh-Hant"].map(AppLanguage.name(of:)) == ["한국어", "영어", "일본어", "중국어(번체)"], "language names must be CLDR names in the UI language")
    // The bare binary that CI's crash diagnosis runs has no bundle to check.
    guard Bundle.main.bundleURL.pathExtension == "app" else { print("PASS: UI language resolution, CLDR names (bare binary: bundle checks skipped)"); return }
    let bundle = Bundle.main
    featureCheck(bundle.developmentLocalization == "ko", "development localization is \(bundle.developmentLocalization ?? "nil"), expected ko")
    featureCheck(["ko", "ja", "zh-Hant"].allSatisfy(bundle.localizations.contains), "bundle localizations \(bundle.localizations) must include ko, ja and zh-Hant")
    featureCheck(Locale.current.language.languageCode?.identifier == "ko", "Locale.current is \(Locale.current.identifier), expected Korean under the ko pin")
    print("PASS: UI language resolution, CLDR names, ko development region, ko/ja/zh-Hant bundle localizations, Korean Locale")
}

// Translated row labels can be wider than the Korean 95 pt column; the rows must then share the widest label's width.
func runSettingsLayoutTests() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    guard let fixture = try? PreviewFixture(uiLanguage: "ko") else { featureCheck(false, "the ko preview fixture must build"); return }
    defer { fixture.close() }
    let delegate = fixture.delegate, content = delegate.window.contentView!
    // The label in front of each picker.
    let labels = [delegate.picker, delegate.targetPicker, delegate.iconPicker].compactMap { ($0.superview as? NSStackView)?.arrangedSubviews.first as? NSTextField }
    func widths() -> [CGFloat] { content.layoutSubtreeIfNeeded(); return labels.map { $0.alignmentRect(forFrame: $0.frame).width } }
    featureCheck(labels.count == 3 && widths() == [95, 95, 95], "the Korean row labels must keep the 95 pt column, got \(widths())")
    labels[2].stringValue = "Menu bar icon styles"
    let shared = widths(), needed = labels[2].intrinsicContentSize.width
    featureCheck(Set(shared).count == 1 && shared[0] >= 95 && shared[0] >= needed, "row labels are \(shared) wide; they must share one width of at least 95 pt that fits the \(needed) pt label")
    print("PASS: settings row labels share one width that fits the longest label")
}

// A process resolves one bundle language, so build.sh runs this once per UI language.
func runLocalizationTest(expected: String, strict: Bool) {
    var errors: [String] = []
    let resolved = AppLanguage.current, locale = Locale.current
    if resolved != expected { errors.append("resolved \(resolved), expected \(expected)") }
    else if locale.language.languageCode != Locale.Language(identifier: expected).languageCode {
        // With another language listed before ko, unsupported system languages keep Korean text but get that language's Locale (午後 in dates).
        errors.append("Locale.current is \(locale.identifier), expected language \(expected); ko must be first in CFBundleLocalizations")
    }
    var detail = "Korean source text", sample: String? = "활성화"
    if expected != "ko" {
        let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: expected)
        let table = url.flatMap { try? PropertyListSerialization.propertyList(from: Data(contentsOf: $0), format: nil) } as? [String: String] ?? [:]
        if table.isEmpty { errors.append("\(expected).lproj/Localizable.strings is missing, unreadable or empty") }
        detail = "\(table.count) translated"
        sample = table.keys.sorted().compactMap { table[$0] }.first { !$0.isEmpty && $0.unicodeScalars.allSatisfy { $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value) } }
        if !table.isEmpty, sample == nil { errors.append("no translation made only of Han or kana to check the \(expected) font") }
    }
    // Untagged text in the system font takes its CJK glyphs from the process language's cascade, which must give the UI language's Apple standard font.
    if let sample {
        let fonts = systemFontGlyphFonts(sample)
        if let standard = ["ko": "AppleSDGothicNeo", "ja": "HiraKakuInterface", "zh-Hant": "PingFangUITextTC"][expected] {
            if fonts.isEmpty || !fonts.allSatisfy({ $0.contains(standard) }) { errors.append("\(sample) in the system font uses \(fonts), expected \(standard)") }
        } else { errors.append("no standard font is known for \(expected)") }
        detail += ", \(sample) in \(fonts.joined(separator: " "))"
    }
    guard errors.isEmpty else { errors.forEach { fputs("FAIL: \(expected) localization: \($0)\n", stderr) }; exit(1) }
    print("PASS: \(expected) localization: resolved \(resolved) (Locale \(locale.identifier)), \(detail)")
}

// PostScript names of the fonts CoreText picks for text drawn in the system font, as AppKit controls draw UI text.
func systemFontGlyphFonts(_ text: String) -> [String] { glyphRunFonts(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])) }
// PostScript names of the fonts CoreText picks for each glyph run, in order, including fallbacks for glyphs the given font lacks.
func glyphRunFonts(_ text: NSAttributedString) -> [String] {
    (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as? [CTRun] ?? []).map { CTFontCopyPostScriptName((CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String }
}
