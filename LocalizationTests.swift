import AppKit

func runLocalizationTests() {
    let field = NSTextField(string: ""), role = field.cell?.accessibilityRoleDescription() ?? ""
    field.setAccessibilityLabel("gksdud \(role)"); let named = repeatedRole(field)
    featureCheck(!role.isEmpty && named == role, "a text field labeled \"gksdud \(role)\" names its role, but the walk's check found \(named ?? "none")")
    field.setAccessibilityLabel("한영 전환 테스트 입력창")
    featureCheck(repeatedRole(field) == nil, "the Korean test field label does not name the role \(role), but the walk's check found it")
    print("PASS: the localization walk finds accessibility labels that name their control's role")
    runScreenshotTests()
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

// The parts of --capture-screenshots that need no screen or Screen Recording, so CI runs them: the offscreen badge strip, the menu's
// capture rectangle with its backdrop, overlap and hover checks, the backdrop placement, blank-file detection and the capture state.
// runLaunchModeTests has its arguments.
func runScreenshotTests() {
    let scratch = URL(fileURLWithPath: "/private/tmp/gksdud-self-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    ScratchDefaults.removeAtExit(scratch)
    defer { try? FileManager.default.removeItem(at: scratch) }
    func failure(_ body: () throws -> Any) -> String { do { _ = try body(); return "" } catch { return error.localizedDescription } }
    // 360 pt at 2x on any display, so the README can show it at half its pixel width.
    let light = scratch.appendingPathComponent("badges.png"), dark = scratch.appendingPathComponent("badges-dark.png")
    do {
        try renderBadgeStrip(primary: .korean, appearance: .aqua, to: light); try renderBadgeStrip(primary: .korean, appearance: .darkAqua, to: dark)
        let size = try screenshotPixels(light)
        featureCheck(size.width == 720 && FileManager.default.contents(atPath: light.path) != FileManager.default.contents(atPath: dark.path),
            "the badge strip is \(size.width) px wide, expected 720 (360 pt at 2x), and must differ in the dark appearance")
    } catch { featureCheck(false, "the badge strip must render offscreen: \(error.localizedDescription)") }
    print("PASS: badge strip renders offscreen")

    // Style rows pair the primary badge with the English one. Glyph rows name a source that shows the glyph, or the language when none does.
    let japanese = badgeStripRows(primary: .japanese, installed: [SampleSource.katakana, SampleSource.kanaHiragana, SampleSource.hiragana, SampleSource.romaji, SampleSource.abc])
    featureCheck(japanese.map(\.text.string) == IconStyle.allCases.map { $0.title(primary: .japanese) } + ["Hiragana", "Katakana"]
        && japanese.map(\.badges) == IconStyle.allCases.map { [$0.badge(for: .japanese), $0.badge(for: .english)] } + ["あ", "ア"].map { [.text($0, filled: true, language: "ja")] },
        "Japanese strip rows are \(japanese.map(\.text.string)) with \(japanese.map(\.badges))")
    let chinese = badgeStripRows(primary: .traditionalChinese, installed: [SampleSource.zhuyin, SampleSource.cangjie, SampleSource.cantonesePhonetic, SampleSource.abc]).dropFirst(IconStyle.allCases.count)
    featureCheck(chinese.map(\.text.string) == [AppLanguage.name(of: "zh-Hant"), "Cangjie – Traditional", "Zhuyin – Traditional"] && chinese.map(\.badges) == ["中", "倉", "注"].map { [.text($0, filled: true, language: "zh-Hant")] },
        "Traditional Chinese glyph rows are \(chinese.map(\.text.string)) with \(chinese.map(\.badges))")
    let stripFonts = badgeStripFontProblems()
    featureCheck(stripFonts.isEmpty, stripFonts.joined(separator: "; "))
    print("PASS: badge strip rows: icon style titles with both badges, one row per glyph named after its source, glyphs in their input language's standard font")

    let me = getpid(), menuLayer = CGWindowLevelForKey(.popUpMenuWindow), backdrop = CGRect(x: 0, y: 0, width: 720, height: 850)
    func window(_ owner: String, _ pid: pid_t, layer: CGWindowLevel, _ bounds: CGRect, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowBounds as String: bounds.dictionaryRepresentation, kCGWindowAlpha as String: alpha]
    }
    let menuBounds = CGRect(x: 100, y: 200, width: 240, height: 300), menu = window("gksdud", me, layer: menuLayer, menuBounds)
    let apart = window("Clock", me + 1, layer: 1000, CGRect(x: 0, y: 0, width: 80, height: 80)), invisible = window("Overlay", me + 1, layer: 1000, CGRect(x: 0, y: 0, width: 4000, height: 4000), alpha: 0)
    let rect = try? menuCaptureRect(windowsAbove: [menu, apart, invisible], process: me, backdrop: backdrop)
    featureCheck(rect == CGRect(x: 88, y: 188, width: 264, height: 324), "the menu capture must be the menu window plus 12 pt, ignoring windows beside it and invisible ones; got \(rect.map { "\($0)" } ?? "an error")")
    let covered = failure { try menuCaptureRect(windowsAbove: [window("Notes", me + 1, layer: 1000, CGRect(x: 330, y: 480, width: 50, height: 50)), menu], process: me, backdrop: backdrop) }
    let missing = failure { try menuCaptureRect(windowsAbove: [window("gksdud", me, layer: 0, CGRect(x: 0, y: 0, width: 384, height: 636))], process: me, backdrop: backdrop) }
    featureCheck(covered.contains("Notes") && covered.contains("move or close it") && missing.contains("status menu is not on screen"), "overlap and missing-menu failures must say what happened: \(covered) / \(missing)")
    // The overlap check sees only the windows above the backdrop, so the rectangle -R takes, in whole points, must lie on the backdrop.
    let narrow = CGRect(x: 90, y: 0, width: 720, height: 850), outside = failure { try menuCaptureRect(windowsAbove: [menu], process: me, backdrop: narrow) }
    let halfPoint = window("gksdud", me, layer: menuLayer, CGRect(x: 100.5, y: 200, width: 240, height: 300))
    let whole = try? menuCaptureRect(windowsAbove: [halfPoint], process: me, backdrop: CGRect(x: 88, y: 0, width: 720, height: 850))
    let past = failure { try menuCaptureRect(windowsAbove: [halfPoint], process: me, backdrop: CGRect(x: 88.5, y: 0, width: 720, height: 850)) }
    featureCheck(outside.contains("\(CGRect(x: 88, y: 188, width: 264, height: 324))") && outside.contains("\(narrow)") && outside.contains("does not fit") && whole == CGRect(x: 88, y: 188, width: 265, height: 324) && past.contains("does not fit"),
        "the capture rectangle in whole points must lie on the backdrop, and a failure must name both: \(outside) / \(whole.map { "\($0)" } ?? "an error") / \(past)")
    // menu.png would show the row under the pointer highlighted, and a pointer that just reached the menu has not highlighted it yet.
    let highlighted = menuHoverProblem(highlighted: "Hiragana", pointer: CGPoint(x: 10, y: 10), menu: menuBounds)
    let pointed = menuHoverProblem(highlighted: nil, pointer: CGPoint(x: 150, y: 250), menu: menuBounds)
    let clear = [CGPoint(x: 10, y: 10), nil].map { menuHoverProblem(highlighted: nil, pointer: $0, menu: menuBounds) }
    featureCheck(highlighted?.contains("\"Hiragana\"") == true && pointed?.contains("pointer is on the menu") == true && [highlighted, pointed].allSatisfy { $0?.contains("keep the pointer off the menu") == true } && clear == [nil, nil],
        "a highlighted item or the pointer on the menu must stop its capture by name: \(highlighted ?? "nil") / \(pointed ?? "nil") / \(clear)")
    let screen = NSRect(x: 0, y: 25, width: 1440, height: 850)
    featureCheck(backdropFrame(screen, pointer: NSPoint(x: 1200, y: 400)) == NSRect(x: 0, y: 25, width: 720, height: 850) && backdropFrame(screen, pointer: NSPoint(x: 100, y: 400)) == NSRect(x: 720, y: 25, width: 720, height: 850),
        "the backdrop must take the half of the screen away from the pointer")
    print("PASS: menu capture: the menu window plus a 12 pt margin in whole points, inside the backdrop, stopped by another app's window over it or by a highlighted item or the pointer on the menu, backdrop away from the pointer")

    let blank = scratch.appendingPathComponent("blank.png"), empty = scratch.appendingPathComponent("empty.png"), absent = scratch.appendingPathComponent("absent.png")
    if let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        context.setFillColor(CGColor(gray: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        try? context.makeImage().map { NSBitmapImageRep(cgImage: $0) }?.representation(using: .png, properties: [:])?.write(to: blank)
    }
    FileManager.default.createFile(atPath: empty.path, contents: Data())
    let problems = [blank, empty, absent].map { file in failure { try screenshotPixels(file) } }
    featureCheck(problems == ["\(blank.path) is a single uniform colour, as a blank capture is", "\(empty.path) is empty", "\(absent.path) is missing"], "blank, empty and missing screenshots must fail by name: \(problems)")
    // What the README screenshots show: trusted, on, key-down switching, long press and preservation on, login off, menu bar on,
    // the first icon style and the default test text, with no update or warning.
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    guard let fixture = try? PreviewFixture(uiLanguage: "ko", state: .capture) else { featureCheck(false, "the capture fixture must build"); return }
    let delegate = fixture.delegate, boxes = [delegate.enabled, delegate.pressSwitch, delegate.longPressSwitch, delegate.preserveCapsSwitch, delegate.login, delegate.showInMenuBar] + delegate.specialButtons
    featureCheck(boxes.map { $0.state == .on } == [true, true, true, true, false, true, false, false] && delegate.pressSwitch.isEnabled && delegate.iconPicker.indexOfSelectedItem == 0
        && fixture.defaults.object(forKey: "testInputText") == nil && delegate.testInput.stringValue == delegate.engine.testInputText && delegate.keyboardWarningRow.isHidden && delegate.statusMenu.items[1].isHidden,
        "the capture state shows \(boxes.map { "\($0.title): \($0.state == .on)" }), icon style \(delegate.iconPicker.indexOfSelectedItem), test text \(delegate.testInput.stringValue)")
    let untouched = fixture.verifyUntouched()
    fixture.close()
    featureCheck(untouched.isEmpty, "the capture fixture reached the live system: \(untouched)")
    print("PASS: capture state and checks: long press on over the default settings, no update or warning, untouched; blank, empty and missing files fail by name")
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
    errors += badgeFontProblems() + badgeStripFontProblems()
    // Saved keyboard choices are keyed by this hash of the untranslated fallback name.
    if KeyboardIdentity(properties: [:]).key != "4a38e0a533f920f053f8ea29fdf2161cd7e84009e4a223a562b4b5fb1a8ab1ec" { errors.append("KeyboardIdentity(properties: [:]).key changed, which would forget saved keyboard choices") }
    let walk = walkUI(expected)
    errors += walk.errors
    if !SystemAccess.denied.isEmpty { errors.append("blocked system actions: \(SystemAccess.denied.joined(separator: ", "))") }
    let korean = expected == "ko" ? [] : walk.strings.filter { containsHangul($0.key) }.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
    let warnings = korean.map { "Korean text in \($0.value): \($0.key)" } + walk.clipped + walk.repeatedRoles
    warnings.forEach { fputs("warning: \(expected) localization: \($0.replacingOccurrences(of: "\n", with: "\\n"))\n", stderr) }
    guard errors.isEmpty else { errors.forEach { fputs("FAIL: \(expected) localization: \($0)\n", stderr) }; exit(1) }
    let summary = "resolved \(resolved) (Locale \(locale.identifier)), \(detail), \(walk.states) states, \(walk.strings.count) strings, \(expected == "ko" ? "" : "\(korean.count) Korean, ")"
        + "\(walk.clipped.count) clipped, \(walk.repeatedRoles.count) labels naming their role, untouched: \(SystemAccess.denied.count) blocked system actions, \(walk.selections) input-source selections"
    guard !strict || warnings.isEmpty else { fputs("FAIL: \(expected) localization: \(warnings.count) warnings in strict mode; \(summary)\n", stderr); exit(1) }
    print("PASS: \(expected) localization: \(summary)")
}

// What the walk saw: every string the UI shows, where it first appeared, the layout problems and the structural errors.
struct UIWalk {
    var strings: [String: String] = [:]
    var clipped: [String] = []
    var repeatedRoles: [String] = []
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
            if let role = repeatedRole(view), let label = view.accessibilityLabel(), reported.insert("\(label) \(role)").inserted {
                walk.repeatedRoles.append("state \(state), \(kind): the accessibility label \"\(label)\" names its role \"\(role)\", which VoiceOver already speaks")
            }
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

// The role a view's accessibility label names. VoiceOver speaks the role after the label, so that role would be heard twice.
// A control's cell carries its role; the control view itself reports an unknown role.
func repeatedRole(_ view: NSView) -> String? {
    guard let label = view.accessibilityLabel(), let role = (view as? NSControl)?.cell?.accessibilityRoleDescription() ?? view.accessibilityRoleDescription(),
          !role.isEmpty, label.localizedCaseInsensitiveContains(role) else { return nil }
    return role
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
// Like the icon style picker, the screenshots' badge strip draws a title's leading glyph in its input language's standard font.
func badgeStripFontProblems() -> [String] {
    InputLanguage.all.filter { !$0.isEnglish }.flatMap { language in
        badgeStripRows(primary: language, installed: []).prefix(IconStyle.allCases.count).compactMap { row -> String? in
            guard row.text.string.unicodeScalars.first.map({ !$0.isASCII }) == true else { return nil }
            let font = glyphRunFonts(row.text).first ?? "no font", standard = standardFonts[language.id] ?? "no standard font"
            return font.contains(standard) ? nil : "the badge strip title \(row.text.string) draws its \(language.id) glyph in \(font), expected \(standard)"
        }
    }
}

// PostScript names of the fonts CoreText picks for text drawn in the system font, as AppKit controls draw UI text.
func systemFontGlyphFonts(_ text: String) -> [String] { glyphRunFonts(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])) }
// PostScript names of the fonts CoreText picks for each glyph run, in order, including fallbacks for glyphs the given font lacks.
func glyphRunFonts(_ text: NSAttributedString) -> [String] {
    (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(text)) as? [CTRun] ?? []).map { CTFontCopyPostScriptName((CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String }
}
