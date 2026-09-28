import AppKit

// The status menu, the input badge in the menu bar and settings, and the icon style previews.
extension AppDelegate {
    var iconStyle: Int { let value = engine.defaults.integer(forKey: "iconStyle"); return (0...3).contains(value) ? value : 0 }
    func iconLabel(korean: Bool) -> String { korean ? (iconStyle == 2 ? "KO" : "한") : ["dud", "A", "EN", "캐릭터"][iconStyle] }
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
        let updateEntry = NSMenuItem(title: "업데이트 가능", action: #selector(showAbout), keyEquivalent: "")
        updateEntry.target = self
        updateEntry.image = updateGlyph(NSSize(width: 22, height: 20))
        updateEntry.isHidden = updates.available == nil
        menu.addItem(updateEntry)
        menu.addItem(NSMenuItem.separator())
        let koreanEntry = menu.addItem(withTitle: "한국어", action: #selector(selectKorean), keyEquivalent: "")
        koreanEntry.target = self; koreanEntry.image = sourceMenuIcon(korean: true)
        let englishEntry = menu.addItem(withTitle: "영어", action: #selector(selectEnglish), keyEquivalent: "")
        englishEntry.target = self; englishEntry.image = sourceMenuIcon(korean: false)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "활성화", action: #selector(menuEnabled), keyEquivalent: "").target = self
        menu.addItem(withTitle: "누를 때 전환", action: #selector(menuPressSwitch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "로그인 시 시작", action: #selector(menuLogin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "메뉴바에 표시", action: #selector(menuHidden), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        let settingsEntry = menu.addItem(withTitle: "설정..", action: #selector(showSettings), keyEquivalent: ",")
        settingsEntry.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {}
    @objc func menuBrand() { showAbout() }
    func sourceMenuIcon(korean: Bool) -> NSImage {
        iconStyle == 3 ? DudIcon.badge(korean: korean) : badgeImage(label: iconLabel(korean: korean), filled: korean)
    }
    @objc func changeIconStyle() {
        engine.defaults.set(iconPicker.indexOfSelectedItem, forKey: "iconStyle")
        refreshIconPreviews()
        updateInputIndicator()
        for entry in statusMenu.items {
            if entry.action == #selector(selectKorean) { entry.image = sourceMenuIcon(korean: true) }
            if entry.action == #selector(selectEnglish) { entry.image = sourceMenuIcon(korean: false) }
        }
    }
    func refreshIconPreviews() {
        koreanPreview.image = sourceMenuIcon(korean: true)
        englishPreview.image = sourceMenuIcon(korean: false)
    }
    func badgeImage(label: String, filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 1.25), xRadius: 3, yRadius: 3)
            NSColor.black.set()
            if filled { shape.fill() } else { shape.lineWidth = 0.8; shape.stroke() }
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: label.count == 1 ? 11.5 : label.count == 2 ? 9 : 8, weight: .semibold), .foregroundColor: NSColor.black
            ])
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
    func availableSource(_ language: InputLanguage) -> InputSource? {
        environment.inputSources.enabled().first { InputLanguage.match($0.language) == language }
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
        let lang = current.language, language = InputLanguage.match(lang)
        updateInputMenuState(language: language)
        let korean = language == .korean, english = language == .english
        let label = korean ? iconLabel(korean: true) : english ? iconLabel(korean: false) : (lang.isEmpty ? "?" : String(lang.prefix(3)))
        // Let the status bar resolve contrast, including its initial appearance and highlighting.
        let badge = korean || english ? sourceMenuIcon(korean: korean) : badgeImage(label: label, filled: false)
        inputBadge.image = badge
        tabButtons.first?.image = badge
        inputBadge.setAccessibilityLabel("현재 입력: \(korean ? "한국어" : english ? "영어" : label)")
        guard let button = item?.button else { return }
        button.title = ""; button.image = badge
        button.imagePosition = .imageOnly
        let warning = engine.keyboards.warning.map { "\n\($0)" } ?? ""
        button.toolTip = "gksdud · 현재 입력 소스: \(lang)\(warning)"
        button.setAccessibilityLabel("gksdud, 현재 입력 \(korean ? "한국어" : english ? "영어" : label)\(warning)")
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
                entry.toolTip = environment.accessibilityTrusted() ? "키를 누르는 순간 전환합니다." : "설정을 열어 접근성 권한 허용 버튼을 표시합니다."
            case #selector(menuLogin): entry.state = login.state
            case #selector(menuHidden): entry.state = showInMenuBar.state
            case #selector(selectKorean): entry.isEnabled = availableSource(.korean) != nil
            case #selector(selectEnglish): entry.isEnabled = availableSource(.english) != nil
            default: break
            }
        }
        menu.autoenablesItems = false
    }
    func menuDidClose(_ menu: NSMenu) {
        menuInputTimer?.invalidate()
        menuInputTimer = nil
    }
    func updateInputMenuState(language: InputLanguage?) {
        for entry in statusMenu.items {
            if entry.action == #selector(selectKorean) { entry.state = language == .korean ? .on : .off }
            if entry.action == #selector(selectEnglish) { entry.state = language == .english ? .on : .off }
        }
    }
    func selectLanguage(_ language: InputLanguage) { if let source = availableSource(language) { rememberCapsBeforeSwitch(); _ = environment.inputSources.select(source.id) }; updateInputIndicator() }
    @objc func selectKorean() { selectLanguage(.korean) }
    @objc func selectEnglish() { selectLanguage(.english) }
}
