import AppKit

extension NSAttributedString.Key {
    static let coreTextLanguage = NSAttributedString.Key(kCTLanguageAttributeName as String)
}

// The status menu, the input badge in the menu bar and settings, and the icon style previews.
extension AppDelegate {
    var iconStyle: IconStyle { IconStyle(saved: engine.defaults.integer(forKey: "iconStyle")) }
    func updateMenu() {
        if showInMenuBar.state == .off { if let item { NSStatusBar.system.removeStatusItem(item) }; item = nil; return }
        guard item == nil else { return }
        item = NSStatusBar.system.statusItem(withLength: 28)
        item?.button?.font = .systemFont(ofSize: 13, weight: .medium)
        if let button = item?.button {
            warningBadge.removeFromSuperview()
            warningBadge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(warningBadge)
            NSLayoutConstraint.activate([
                warningBadge.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 1),
                warningBadge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
                warningBadge.widthAnchor.constraint(equalToConstant: 9),
                warningBadge.heightAnchor.constraint(equalToConstant: 9)
            ])
            warningBadge.isHidden = engine.keyboards.warning == nil
        }
        item?.menu = statusMenu
        updateInputIndicator()
    }
    // No status item here, so previews and tests can build the menu; menuNeedsUpdate adds the input rows after the first separator.
    func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let brandEntry = NSMenuItem(title: "gksdud", action: #selector(menuBrand), keyEquivalent: "")
        brandEntry.attributedTitle = NSAttributedString(string: "gksdud", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .heavy), .kern: 0.6])
        brandEntry.image = DudIcon.badge(korean: false)
        brandEntry.target = self
        brandEntry.isEnabled = true
        menu.addItem(brandEntry)
        let updateEntry = NSMenuItem(title: String(localized: "업데이트 가능", comment: "Status menu: item shown while a newer version is available; it opens the About tab."), action: #selector(showAbout), keyEquivalent: "")
        updateEntry.target = self
        updateEntry.image = updateGlyph(NSSize(width: 22, height: 20))
        updateEntry.isHidden = updates.available == nil
        menu.addItem(updateEntry)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: String(localized: "활성화", comment: "Status menu: toggles gksdud on and off, like the General tab checkbox of the same name."), action: #selector(menuEnabled), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "누를 때 전환", comment: "Status menu: toggles switching the input source when the key goes down instead of up, like the General tab checkbox of the same name."), action: #selector(menuPressSwitch), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "로그인 시 시작", comment: "Status menu: toggles opening gksdud at login, like the General tab checkbox of the same name."), action: #selector(menuLogin), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "메뉴바에 표시", comment: "Status menu: toggles the gksdud menu bar icon, like the General tab checkbox of the same name."), action: #selector(menuHidden), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        let settingsEntry = menu.addItem(withTitle: String(localized: "설정..", comment: "Status menu: opens the settings window (⌘,)."), action: #selector(showSettings), keyEquivalent: ",")
        settingsEntry.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: String(localized: "종료", comment: "Status menu: quits gksdud (⌘Q)."), action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }
    // Rebuilt on every open, so the rows follow the enabled sources and the icon style.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        let style = iconStyle, rows = InputMenu.rows(enabled: environment.inputSources.enabled(), current: environment.inputSources.current())
        menu.items.filter { $0.action == #selector(selectInputSource(_:)) }.forEach(menu.removeItem)
        let start = (menu.items.firstIndex { $0.isSeparatorItem } ?? menu.numberOfItems - 1) + 1
        for (offset, row) in rows.enumerated() {
            let entry = NSMenuItem(title: row.title, action: #selector(selectInputSource(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = row.source.id
            entry.image = Self.badgeImage(style.badge(for: row.source)); entry.state = row.checked ? .on : .off
            menu.insertItem(entry, at: start + offset)
        }
    }
    @objc func menuBrand() { showAbout() }
    @objc func changeIconStyle() {
        engine.defaults.set(iconPicker.indexOfSelectedItem, forKey: "iconStyle")
        refreshIconPreviews()
        updateInputIndicator()
    }
    // The language the previews and icon style titles show next to English.
    func primaryLanguage() -> InputLanguage { InputMenu.primaryLanguage(current: environment.inputSources.current(), enabled: environment.inputSources.enabled) }
    func refreshIconPreviews() {
        let primary = primaryLanguage(), style = iconStyle
        // In place, because NSPopUpButton drops a duplicate title and would shift the saved index.
        for (index, style) in IconStyle.allCases.enumerated() {
            iconPicker.item(at: index)?.attributedTitle = Self.iconStyleTitle(style, primary: primary, font: iconPicker.font ?? .systemFont(ofSize: NSFont.systemFontSize))
        }
        for (preview, language) in [(languagePreview, primary), (englishPreview, .english)] {
            preview.image = Self.badgeImage(style.badge(for: language))
            preview.setAccessibilityLabel(String(localized: "\(language.displayName) 아이콘 미리보기", comment: "General tab: accessibility label of a menu bar icon preview next to the icon picker. %@ is an input language name, such as Japanese or English."))
        }
    }
    static func badgeImage(_ badge: InputBadge) -> NSImage {
        switch badge {
        case let .text(label, filled, language): return badgeImage(label: label, filled: filled, language: language)
        case let .face(face): return DudIcon.badge(korean: face == .hieut)
        }
    }
    // Only the glyph before " / " names the input language; the rest is UI text in the UI language's font.
    static func iconStyleTitle(_ style: IconStyle, primary: InputLanguage, font: NSFont) -> NSAttributedString {
        let title = style.title(primary: primary), text = NSMutableAttributedString(string: title, attributes: [.font: font])
        text.addAttribute(.coreTextLanguage, value: primary.id, range: NSRange(location: 0, length: min((title as NSString).range(of: " / ").location, text.length)))
        return text
    }
    // The badge names its input language, so CoreText takes Han and kana shapes (中 注 あ) from that language, not the UI language.
    static func badgeText(_ label: String, language: String?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: label.count == 1 ? 11.5 : label.count == 2 ? 9 : 8, weight: .semibold), .foregroundColor: NSColor.black]
        attributes[.coreTextLanguage] = language
        return NSAttributedString(string: label, attributes: attributes)
    }
    static func badgeImage(label: String, filled: Bool, language: String?) -> NSImage {
        let text = badgeText(label, language: language)
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 1.25), xRadius: 3, yRadius: 3)
            NSColor.black.set()
            if filled { shape.fill() } else { shape.lineWidth = 0.8; shape.stroke() }
            let size = text.size()
            let origin = NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)
            if filled {
                let mask = NSImage(size: rect.size, flipped: false) { _ in text.draw(at: origin); return true }
                mask.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
            } else { text.draw(at: origin) }
            return true
        }
        image.isTemplate = true
        return image
    }
    @objc func inputSourceChanged() {
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            guard let self else { return }
            guard !self.optionInput.busy else { return }
            self.completeCapsTransition()
            self.scheduleCapsRestore()
            self.restoreEnglishCaps()
            self.updateInputIndicator()
        }
    }
    func updateInputIndicator() {
        // The Option-character round trip selects English for a moment; didFinish refreshes afterwards.
        guard !optionInput.busy else { return }
        guard let current = environment.inputSources.current() else { return }
        updateInputMenuState(current: current)
        // Let the status bar resolve contrast, including its initial appearance and highlighting.
        let badge = Self.badgeImage(iconStyle.badge(for: current)), name = languageName(of: current)
        inputBadge.image = badge
        tabButtons.first?.image = badge
        inputBadge.setAccessibilityLabel(String(localized: "현재 입력: \(name)", comment: "General tab: accessibility label of the input badge next to the test field. %@ is the current input language, such as Japanese."))
        if window?.isVisible == true { refreshIconPreviews() }
        guard let button = item?.button else { return }
        button.title = ""; button.image = badge
        button.imagePosition = .imageOnly
        let warning = engine.keyboards.warning.map { "\n\($0)" } ?? ""
        button.toolTip = String(localized: "gksdud · 현재 입력 소스: \(current.language)", comment: "Menu bar icon tooltip. %@ is the language tag of the current input source, such as ko or ja.") + warning
        button.setAccessibilityLabel(String(localized: "gksdud, 현재 입력 \(name)", comment: "Menu bar icon accessibility label. %@ is the current input language, such as Japanese.") + warning)
    }
    func menuWillOpen(_ menu: NSMenu) {
        updateInputIndicator()
        // Menu tracking can delay input-source notifications. Keep the open menu
        // and settings badge current without running hardware repair in this mode.
        menuInputTimer?.invalidate()
        let refresh = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateInputIndicator()
        }
        menuInputTimer = refresh
        RunLoop.main.add(refresh, forMode: .eventTracking)
        login.state = environment.loginItemStatus() == .enabled ? .on : .off
        for entry in menu.items {
            switch entry.action {
            case #selector(menuEnabled): entry.state = engine.active ? .on : .off
            case #selector(menuPressSwitch):
                entry.state = environment.accessibilityTrusted() && engine.switchOnKeyDown ? .on : .off
                entry.isEnabled = true
                entry.toolTip = environment.accessibilityTrusted() ? String(localized: "키를 누르는 순간 전환합니다.", comment: "Status menu: tooltip of the switch-on-key-down item while accessibility access is granted.")
                    : String(localized: "설정을 열어 접근성 권한 허용 버튼을 표시합니다.", comment: "Status menu: tooltip of the switch-on-key-down item without accessibility access; choosing it opens settings at the button that requests access.")
            case #selector(menuLogin): entry.state = login.state
            case #selector(menuHidden): entry.state = showInMenuBar.state
            default: break
            }
        }
        menu.autoenablesItems = false
    }
    func menuDidClose(_ menu: NSMenu) {
        menuInputTimer?.invalidate()
        menuInputTimer = nil
    }
    func updateInputMenuState(current: InputSource?) {
        for entry in statusMenu.items where entry.action == #selector(selectInputSource(_:)) {
            entry.state = entry.representedObject as? String == current?.id ? .on : .off
        }
    }
    // Each row is one concrete source, so choosing it never falls back to another source of its language.
    @objc func selectInputSource(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { rememberCapsBeforeSwitch(); _ = environment.inputSources.select(id) }
        updateInputIndicator()
    }
}
