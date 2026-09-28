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
        if let standard = standardFonts[expected] {
            if fonts.isEmpty || !fonts.allSatisfy({ $0.contains(standard) }) { errors.append("\(sample) in the system font uses \(fonts), expected \(standard)") }
        } else { errors.append("no standard font is known for \(expected)") }
        detail += ", \(sample) in \(fonts.joined(separator: " "))"
    }
    // Badges name their input language, so its font must win over the UI language's cascade.
    errors += badgeFontProblems()
    // Saved keyboard choices are keyed by this hash of the untranslated fallback name.
    if KeyboardIdentity(properties: [:]).key != "4a38e0a533f920f053f8ea29fdf2161cd7e84009e4a223a562b4b5fb1a8ab1ec" { errors.append("KeyboardIdentity(properties: [:]).key changed, which would forget saved keyboard choices") }
    let walk = walkUI(expected)
    errors += walk.errors
    if !SystemAccess.denied.isEmpty { errors.append("blocked system actions: \(SystemAccess.denied.joined(separator: ", "))") }
    let korean = expected == "ko" ? [] : walk.strings.filter { containsHangul($0.key) }.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
    let warnings = korean.map { "Korean text in \($0.value): \($0.key)" } + walk.clipped
    warnings.forEach { fputs("warning: \(expected) localization: \($0.replacingOccurrences(of: "\n", with: "\\n"))\n", stderr) }
    guard errors.isEmpty else { errors.forEach { fputs("FAIL: \(expected) localization: \($0)\n", stderr) }; exit(1) }
    let summary = "resolved \(resolved) (Locale \(locale.identifier)), \(detail), \(walk.states) states, \(walk.strings.count) strings, \(expected == "ko" ? "" : "\(korean.count) Korean, ")"
        + "\(walk.clipped.count) clipped, untouched: \(SystemAccess.denied.count) blocked system actions, \(walk.selections) input-source selections"
    guard !strict || warnings.isEmpty else { fputs("FAIL: \(expected) localization: \(warnings.count) warnings in strict mode; \(summary)\n", stderr); exit(1) }
    print("PASS: \(expected) localization: \(summary)")
}

// What the walk saw: every string the UI shows, where it first appeared, the layout problems and the structural errors.
struct UIWalk {
    var strings: [String: String] = [:]
    var clipped: [String] = []
    var errors: [String] = []
    var states = 0, selections = 0
}

// The real settings window, keyboard sheet, status menu and main menu, built on PreviewFixture and never ordered on screen.
func walkUI(_ language: String) -> UIWalk {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    var walk = UIWalk(), reported: Set<String> = []
    // A: trusted, no update, no warning. B: no accessibility access, and keyboards off unless chosen, so none is remapped.
    // C: an update, the keyboard warning with a disconnected keyboard, and the long-press failure.
    let states = [("A", PreviewState()), ("B", PreviewState(trusted: false, keyboardDefault: false)),
                  ("C", PreviewState(updateAvailable: true, keyboardWarning: true, longPressFailure: true))]
    for (state, preview) in states {
        let fixture: PreviewFixture
        do { fixture = try PreviewFixture(uiLanguage: language, state: preview, resolveNames: true) } catch { walk.errors.append(error.localizedDescription); break }
        let delegate = fixture.delegate, keyboardNames = Set(delegate.engine.keyboards.keyboards.map(\.displayName))
        func collect(_ text: String?, _ place: String) {
            guard let text, !text.isEmpty, !keyboardNames.contains(text), walk.strings[text] == nil else { return }
            walk.strings[text] = "state \(state), \(place)"
        }
        // Views in a scroll view may extend past the window; only their text and fit are checked.
        func visit(_ view: NSView, _ place: String, in content: NSView, built size: NSSize, scrolled: Bool = false) {
            let place = delegate.tabPanels.firstIndex { $0 === view }.map { "settings \(delegate.tabButtons[$0].title) tab" } ?? place, kind = "\(place), \(type(of: view))"
            switch view {
            // The test field's text is editable, but here it is the localized default the screenshots show.
            case let field as NSTextField: collect(field.stringValue, kind); collect(field.placeholderString, "\(kind) placeholder")
            case let popup as NSPopUpButton: popup.itemTitles.forEach { collect($0, "\(kind) item") }
            case let button as NSButton: collect(button.title, kind); collect(button.alternateTitle, kind)
            case let control as NSSegmentedControl:
                for segment in 0..<control.segmentCount { collect(control.label(forSegment: segment), kind); collect(control.toolTip(forSegment: segment), "\(kind) tooltip") }
            case let image as NSImageView: collect(image.image?.accessibilityDescription, "\(kind) image description")
            default: break
            }
            collect(view.toolTip, "\(kind) tooltip"); collect(view.accessibilityLabel(), "\(kind) accessibility label")
            if !view.isHiddenOrHasHiddenAncestor, let problem = layoutProblem(view, in: content, built: size, scrolled: scrolled), reported.insert(problem).inserted { walk.clipped.append("state \(state), \(place): \(problem)") }
            view.subviews.forEach { visit($0, place, in: content, built: size, scrolled: scrolled || $0 is NSClipView) }
        }
        // Text resists compression (750) more than a window keeps its size (500), so content that needs more room grows the window.
        // Pinned back to its built size just above that priority, the window shows the controls that would have to shrink as clipped.
        func pin(_ name: String, _ content: NSView, built size: NSSize) {
            content.layoutSubtreeIfNeeded()
            let now = content.frame.size
            guard now.width > size.width + 1 || now.height > size.height + 1 else { return }
            let problem = "the \(name) grows from \(Int(size.width))×\(Int(size.height)) to \(Int(now.width))×\(Int(now.height)) pt to fit its content"
            if reported.insert(problem).inserted { walk.clipped.append("state \(state), \(problem); checked at its built size") }
            for pin in [content.widthAnchor.constraint(equalToConstant: size.width), content.heightAnchor.constraint(equalToConstant: size.height)] { pin.priority = .init(751); pin.isActive = true }
            content.layoutSubtreeIfNeeded()
        }
        func visitMenu(_ menu: NSMenu, _ place: String) {
            collect(menu.title, "\(place) title")
            // The menu bar shows a submenu's title, not its item's placeholder title.
            for item in menu.items where !item.isSeparatorItem {
                if let submenu = item.submenu { visitMenu(submenu, "\(place), \(submenu.title) menu"); continue }
                collect(item.title, "\(place) item"); collect(item.toolTip, "\(place) item tooltip")
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let window = delegate.window!, content = window.contentView!
        collect(window.title, "settings window title")
        // Hidden tab panels keep their constraints, so one check covers every tab.
        pin("settings window", content, built: fixture.settingsSize)
        for tab in delegate.tabPanels.indices {
            delegate.selectTab(tab); content.layoutSubtreeIfNeeded()
            visit(content, "settings window", in: content, built: fixture.settingsSize)
        }
        let sheet = fixture.keyboardSettings.window, sheetContent = sheet.contentView!
        collect(sheet.title, "keyboard sheet title")
        sheetContent.layoutSubtreeIfNeeded()
        // A table makes its row views only when it draws them.
        let rows = descendants(sheetContent).compactMap { $0 as? NSTableView }.flatMap { table in (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) } }
        pin("keyboard sheet", sheetContent, built: fixture.sheetSize)
        visit(sheetContent, "keyboard sheet", in: sheetContent, built: fixture.sheetSize)
        rows.filter { $0.window == nil }.forEach { visit($0, "keyboard sheet row", in: sheetContent, built: fixture.sheetSize, scrolled: true) }
        delegate.menuNeedsUpdate(delegate.statusMenu); delegate.menuWillOpen(delegate.statusMenu); delegate.menuDidClose(delegate.statusMenu)
        visitMenu(delegate.statusMenu, "status menu"); visitMenu(fixture.mainMenu, "main menu")
        // NSPopUpButton drops a duplicate title, which would shift the saved choice.
        for (name, picker) in [("icon style", delegate.iconPicker), ("switch key", delegate.picker)] where picker.numberOfItems != 4 || Set(picker.itemTitles).count != 4 {
            walk.errors.append("state \(state): the \(name) picker shows \(picker.itemTitles); it needs 4 different titles")
        }
        let model = InputMenu.rows(enabled: fixture.inputs.enabled, current: fixture.inputs.current).map { "\($0.title) \($0.source.id) \($0.checked)" }
        let shown = delegate.statusMenu.items.filter { $0.action == #selector(AppDelegate.selectInputSource(_:)) }.map { "\($0.title) \($0.representedObject as? String ?? "") \($0.state == .on)" }
        if shown != model { walk.errors.append("state \(state): the status menu rows \(shown) differ from InputMenu.rows \(model)") }
        walk.errors += fixture.verifyUntouched().map { "state \(state): \($0)" }
        if !fixture.inputs.selected.isEmpty { walk.errors.append("state \(state): the walk selected input sources \(fixture.inputs.selected)") }
        walk.selections += fixture.inputs.selected.count; walk.states += 1
        fixture.close()
    }
    return walk
}

// Text wider or taller than its control, or a control outside the window's built size. Image views scale, so only their position is checked.
func layoutProblem(_ view: NSView, in content: NSView, built size: NSSize, scrolled: Bool) -> String? {
    let frame = view.alignmentRect(forFrame: view.frame)
    let text = (view as? NSTextField)?.stringValue ?? (view as? NSButton)?.title ?? view.accessibilityLabel() ?? "", name = "\(type(of: view)) \"\(text)\""
    // Editable fields scroll and truncating ones end in an ellipsis. A wrapping label must fit its lines at its width.
    if let field = view as? NSTextField, let cell = field.cell, !field.isEditable, !field.stringValue.isEmpty, ![.byTruncatingHead, .byTruncatingMiddle, .byTruncatingTail].contains(field.lineBreakMode) {
        if cell.wraps {
            let height = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: .greatestFiniteMagnitude)).height
            if height > field.bounds.height + 1 { return "\(name) needs \(height) pt of height, has \(field.bounds.height) pt" }
        } else if field.intrinsicContentSize.width > frame.width + 1 { return "\(name) needs \(field.intrinsicContentSize.width) pt, has \(frame.width) pt" }
    } else if (view as? NSButton).map({ !$0.title.isEmpty }) ?? (view is NSSegmentedControl), view.intrinsicContentSize.width > frame.width + 1 {
        return "\(name) needs \(view.intrinsicContentSize.width) pt, has \(frame.width) pt"
    }
    // Controls only, so the stack views around one wide row do not repeat it.
    guard !scrolled, view is NSControl, !frame.isEmpty, let superview = view.superview else { return nil }
    let shown = content.convert(frame, from: superview)
    return NSRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1).contains(shown) ? nil : "\(name) at \(shown) is outside the \(Int(size.width))×\(Int(size.height)) pt window"
}

// Hangul Jamo, compatibility Jamo, Jamo extensions A and B, and syllables.
func containsHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in [0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xD7B0...0xD7FF].contains { $0.contains(scalar.value) } }
}

// Apple's standard fonts for each language's CJK text, as CoreText resolves them; PostScript names start with these.
let standardFonts = ["ko": "AppleSDGothicNeo", "ja": "HiraKakuInterface", "zh-Hant": "PingFangUITextTC", "yue-Hant": "PingFangUITextHK"]

// Every label a badge draws, laid out with the badge's own attributes, must come from its input language's standard font
// whatever the UI language. Latin letters stay in the badge's own font.
func badgeFontProblems() -> [String] {
    InputLanguage.all.flatMap { language -> [String] in
        let modes = [nil] + language.modeGlyphs.keys.sorted().map { Optional($0) }
        let labels = Set(modes.flatMap { mode in IconStyle.allCases.compactMap { style -> String? in
            if case let .text(label, _, _) = style.badge(for: language, mode: mode) { return label }; return nil } })
        return labels.sorted().compactMap { label in
            let text = AppDelegate.badgeText(label, language: language.id), fonts = glyphRunFonts(text)
            let own = (text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { CTFontCopyPostScriptName($0 as CTFont) as String }
            guard let expected = label.unicodeScalars.allSatisfy(\.isASCII) ? own : standardFonts[language.id] else { return "\(language.id) badge \(label) has no standard font to check" }
            return !fonts.isEmpty && fonts.allSatisfy({ $0.contains(expected) }) ? nil : "\(language.id) badge \(label) is drawn in \(fonts), expected \(expected)"
        }
    }
}

// PostScript names of the fonts CoreText picks for text drawn in the system font, as AppKit controls draw UI text.
func systemFontGlyphFonts(_ text: String) -> [String] { glyphRunFonts(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])) }
// PostScript names of the fonts CoreText picks for each glyph run, in order, including fallbacks for glyphs the given font lacks.
func glyphRunFonts(_ text: NSAttributedString) -> [String] {
    (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as? [CTRun] ?? []).map { CTFontCopyPostScriptName((CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String }
}
