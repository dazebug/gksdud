import AppKit
import ServiceManagement

extension AppDelegate {
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 636), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "gksdud"; window.isReleasedWhenClosed = false
        window.delegate = self; window.hidesOnDeactivate = false; window.center()
        let content = window.contentView!
        func column() -> NSStackView {
            let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = 16
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
        func full(_ view: NSView, in stack: NSStackView) {
            stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let root = column(); root.spacing = 28; content.addSubview(root)
        inputBadge.contentTintColor = .labelColor; inputBadge.imageScaling = .scaleProportionallyUpOrDown
        inputBadge.widthAnchor.constraint(equalToConstant: 36).isActive = true
        inputBadge.heightAnchor.constraint(equalToConstant: 34).isActive = true
        testInput.stringValue = engine.testInputText; testInput.delegate = self
        testInput.font = .monospacedSystemFont(ofSize: 21, weight: .medium)
        testInput.placeholderString = String(localized: "한영 전환을 테스트해보세요", comment: "General tab: placeholder of the empty switch test field. The Korean says try switching between Korean and English; translate it as trying the input source switch.")
        testInput.setAccessibilityLabel(String(localized: "한영 전환 테스트 입력창", comment: "General tab: accessibility label of the text field for trying the input source switch."))
        testInput.cell?.isScrollable = true; testInput.cell?.wraps = false
        testInput.usesSingleLineMode = true; testInput.lineBreakMode = .byClipping
        testInput.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let inputRow = NSStackView(views: [inputBadge, testInput]); inputRow.spacing = 12; inputRow.alignment = .centerY
        full(inputRow, in: root)
        testInput.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        let host = NSView(); full(host, in: root)
        for _ in 0..<4 {
            let panel = column(); host.addSubview(panel)
            NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: host.leadingAnchor), panel.trailingAnchor.constraint(equalTo: host.trailingAnchor), panel.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor),
                tabPanels.count == 3 ? panel.centerYAnchor.constraint(equalTo: host.centerYAnchor) : panel.topAnchor.constraint(equalTo: host.topAnchor)])
            tabPanels.append(panel)
        }
        let primary = primaryLanguage()
        let tabs = NSStackView(); tabs.distribution = .fillEqually; tabs.spacing = 8
        tabs.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(tabs)
        let titles = [String(localized: "일반", comment: "Settings window: title of the General tab button."), String(localized: "대소문자", comment: "Settings window: title of the tab button for uppercase and lowercase (Caps Lock) settings."),
                      String(localized: "특수문자", comment: "Settings window: title of the tab button for special characters typed with Option."), "gksdud"]
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(changeTab(_:)))
            button.tag = index; button.setButtonType(.toggle); button.bezelStyle = .regularSquare
            button.isBordered = false; button.imagePosition = .imageAbove; button.imageScaling = .scaleProportionallyDown
            button.font = .systemFont(ofSize: 10)
            button.image = index == 0 ? Self.badgeImage(iconStyle.badge(for: primary)) : tabGlyph(["", "Aa", "⌥", "?"][index])
            button.setAccessibilityLabel(tabAccessibilityLabel(title))
            tabs.addArrangedSubview(button); tabButtons.append(button)
        }
        let tabLine = NSBox(); tabLine.boxType = .separator
        tabLine.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(tabLine)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(status)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            status.bottomAnchor.constraint(equalTo: tabLine.topAnchor, constant: -8),
            tabLine.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabLine.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabLine.bottomAnchor.constraint(equalTo: tabs.topAnchor, constant: -5),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5),
            tabs.heightAnchor.constraint(equalToConstant: 42)
        ])
        func hint(_ text: String, in panel: NSStackView, indent: CGFloat = 20) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView(); container.addSubview(label)
            if let last = panel.arrangedSubviews.last { panel.setCustomSpacing(6, after: last) }
            full(container, in: panel)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent), label.trailingAnchor.constraint(equalTo: container.trailingAnchor), label.topAnchor.constraint(equalTo: container.topAnchor), label.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        }
        func separator(in panel: NSStackView) { let line = NSBox(); line.boxType = .separator; full(line, in: panel) }
        func row(_ title: String, _ views: [NSView], in panel: NSStackView) {
            let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 95).isActive = true
            let row = NSStackView(views: [label] + views); row.spacing = 16; row.alignment = .centerY
            panel.addArrangedSubview(row)
        }
        let general = tabPanels[0]
        enabled.target = self; enabled.action = #selector(toggleEnabled); enabled.state = engine.active ? .on : .off
        keyboardWarning.font = .systemFont(ofSize: 11); keyboardWarning.textColor = .systemOrange
        let warningIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: String(localized: "경고", comment: "General tab: accessibility description of the orange icon before the keyboard warning."))!)
        warningIcon.contentTintColor = .systemOrange
        warningIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        keyboardWarningRow.addArrangedSubview(warningIcon); keyboardWarningRow.addArrangedSubview(keyboardWarning)
        keyboardWarningRow.alignment = .top; keyboardWarningRow.spacing = 5
        let activation = NSStackView(views: [enabled, keyboardWarningRow])
        activation.orientation = .vertical; activation.alignment = .leading; activation.spacing = 6
        full(activation, in: general); keyboardWarningRow.isHidden = true
        pressSwitch.target = self; pressSwitch.action = #selector(togglePressSwitch)
        pressAccess.target = self; pressAccess.action = #selector(requestPressAccess); pressAccess.bezelStyle = .rounded
        let pressRow = NSStackView(views: [pressSwitch, pressAccess]); pressRow.spacing = 16; pressRow.alignment = .centerY
        general.addArrangedSubview(pressRow)
        hint(String(localized: "버튼을 뗄 때가 아닌 누를 때 전환하도록 해 더 빠르게 전환합니다.\n글자 씹힘도 더 개선됩니다.", comment: "General tab: two-line hint under the switch-on-key-down checkbox. Switching when the key goes down, not when it is released, is faster and loses fewer typed characters."), in: general)
        separator(in: general)
        picker.addItems(withTitles: sourceKeyTitles)
        picker.selectItem(at: sources.firstIndex(of: engine.source) ?? 0)
        picker.target = self; picker.action = #selector(selectionChanged)
        row(String(localized: "한영 키", comment: "General tab: label of the switch key picker. The Korean names the key that switches between Korean and English; translate it as the key that switches input sources."), [picker], in: general)
        targetPicker.addItems(withTitles: targets.map(\.name)); targetPicker.selectItem(withTitle: engine.target.name)
        targetPicker.target = self; targetPicker.action = #selector(selectionChanged)
        row(String(localized: "내부 전환 키", comment: "General tab: label of the internal switch key picker (F13-F20). gksdud turns the switch key into this key and makes it the system's \"Select the previous input source\" shortcut."), [targetPicker], in: general)
        hint(String(localized: "시스템의 '이전 입력 소스 선택' 단축키의 값을 변경합니다.\n다른 앱과 겹치지 않는, 기능 없는 키를 골라주세요.", comment: "General tab: two-line hint under the internal switch key picker. Quote Apple's own name of the \"Select the previous input source\" shortcut. The second line asks for a key with no function that no other app uses."), in: general)
        let keyboards = NSButton(title: String(localized: "대상 키보드 설정", comment: "General tab: button that opens the sheet choosing the keyboards whose switch key gksdud remaps."), target: self, action: #selector(showKeyboardSettings)); keyboards.bezelStyle = .rounded
        general.addArrangedSubview(keyboards)
        separator(in: general)
        login.target = self; login.action = #selector(toggleLogin)
        login.state = environment.loginItemStatus() == .enabled ? .on : .off
        showInMenuBar.target = self; showInMenuBar.action = #selector(toggleHidden)
        showInMenuBar.state = engine.defaults.bool(forKey: "hidden") ? .off : .on
        general.addArrangedSubview(login); general.addArrangedSubview(showInMenuBar)
        hint(String(localized: "기존 메뉴바 입력기를 대체합니다.\n⌘+드래그로 위치를 옮길 수 있어요.", comment: "General tab: two-line hint under the menu bar checkbox. The gksdud icon replaces the system's input menu, and ⌘-dragging moves it."), in: general)
        iconPicker.addItems(withTitles: IconStyle.allCases.map { $0.title(primary: primary) })
        iconPicker.selectItem(at: iconStyle.rawValue); iconPicker.target = self; iconPicker.action = #selector(changeIconStyle)
        iconPicker.setAccessibilityLabel(String(localized: "메뉴바 아이콘 조합", comment: "General tab: accessibility label of the menu bar icon style picker, whose items pair an input language badge with an English one."))
        for preview in [languagePreview, englishPreview] {
            preview.widthAnchor.constraint(equalToConstant: 22).isActive = true
            preview.heightAnchor.constraint(equalToConstant: 20).isActive = true; preview.contentTintColor = .labelColor
        }
        row(String(localized: "메뉴바 아이콘", comment: "General tab: label of the menu bar icon style picker and its previews."), [iconPicker, languagePreview, englishPreview], in: general)
        let caps = tabPanels[1]
        longPressSwitch.target = self; longPressSwitch.action = #selector(toggleLongPress)
        preserveCapsSwitch.target = self; preserveCapsSwitch.action = #selector(togglePreserveCaps)
        caps.addArrangedSubview(longPressSwitch)
        hint(String(localized: "누른 즉시 한영 전환, 길게 유지시 대소문자 전환", comment: "Case tab: hint under the long-press checkbox. A press switches the input source at once; holding the key toggles uppercase and lowercase."), in: caps)
        caps.addArrangedSubview(preserveCapsSwitch)
        let symbols = tabPanels[2]
        let specialTitles = [String(localized: "영어처럼 특수문자 입력", comment: "Special characters tab: checkbox. Option characters are typed as in English even in Korean input. It works only for Korean input; say so in translations."),
                             String(localized: "Option 문자 입력 차단", comment: "Special characters tab: checkbox that blocks Option characters, so Option with a letter types the plain letter. It works in every input language.")]
        for (index, title) in specialTitles.enumerated() {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(changeSpecialMode(_:)))
            button.tag = index + 1; specialButtons.append(button); symbols.addArrangedSubview(button)
            hint(index == 0 ? String(localized: "한글 상태에서도 ⌥8 → • 처럼 입력합니다.", comment: "Special characters tab: hint under the type-like-English checkbox: in Korean input, ⌥8 still types •. Name Korean input explicitly in translations, because the option works only there.")
                : String(localized: "⌥+문자를 일반 문자로 입력합니다.", comment: "Special characters tab: hint under the Option block checkbox: ⌥ with a letter types the plain letter."), in: symbols)
        }
        specialStatus.font = .systemFont(ofSize: 11); specialStatus.textColor = .secondaryLabelColor
        full(specialStatus, in: symbols)
        let about = tabPanels[3]; about.alignment = .centerX; about.spacing = 18
        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        about.addArrangedSubview(appIcon)
        let name = NSTextField(labelWithString: "gksdud"); name.font = .systemFont(ofSize: 20, weight: .semibold)
        about.setCustomSpacing(12, after: appIcon); about.addArrangedSubview(name)
        updateHeading.font = .systemFont(ofSize: 12); updateHeading.textColor = .secondaryLabelColor; updateHeading.alignment = .center
        about.setCustomSpacing(4, after: name); full(updateHeading, in: about)
        updateScroll.hasVerticalScroller = true; updateScroll.borderType = .bezelBorder
        updateScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        updateSummary.isEditable = false; updateSummary.isSelectable = true
        updateSummary.font = .systemFont(ofSize: 12); updateSummary.textColor = .labelColor
        updateSummary.textContainerInset = NSSize(width: 8, height: 8)
        updateSummary.isHorizontallyResizable = false; updateSummary.isVerticallyResizable = true
        updateSummary.autoresizingMask = [.width]; updateSummary.textContainer?.widthTracksTextView = true
        updateScroll.documentView = updateSummary; full(updateScroll, in: about)
        updateButton.target = self; updateButton.action = #selector(performUpdate); updateButton.bezelStyle = .rounded
        checkUpdateButton.target = self; checkUpdateButton.action = #selector(checkForUpdates); checkUpdateButton.bezelStyle = .rounded
        let actions = NSStackView(views: [updateButton, checkUpdateButton]); actions.spacing = 10; about.addArrangedSubview(actions)
        updateStatus.font = .systemFont(ofSize: 11); updateStatus.textColor = .secondaryLabelColor; updateStatus.alignment = .center
        about.setCustomSpacing(8, after: actions); full(updateStatus, in: about)
        about.setCustomSpacing(28, after: updateStatus)
        let project = NSButton(title: "GitHub", target: self, action: #selector(openProject)); project.bezelStyle = .rounded
        if let url = Bundle.main.url(forResource: "github", withExtension: "svg"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 16, height: 16); image.isTemplate = true
            project.image = image; project.imagePosition = .imageLeading
        }
        let support = NSButton(title: String(localized: "후원", comment: "About tab: button that opens the page for sponsoring the developer."), target: self, action: #selector(openSupport)); support.bezelStyle = .rounded
        support.isHidden = supportURL == nil
        about.addArrangedSubview(NSStackView(views: [project, support]))
        let credit = NSTextField(labelWithString: "© 2026 CodingNoye · codingnoye@gmail.com")
        credit.font = .systemFont(ofSize: 10); credit.textColor = .secondaryLabelColor
        about.addArrangedSubview(credit)
        selectTab(0); updatePressAccess(); refreshSpecialMode(); refreshUpdates(); refreshIconPreviews(); refreshKeyboardState(); updateInputIndicator()
    }
    func tabGlyph(_ text: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 20), flipped: false) { rect in
            let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.black])
            let size = label.size(); label.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)); return true
        }
        image.isTemplate = true; return image
    }
    // Up arrow in a circle, centered in the canvas so it lines up with the other menu icons.
    func updateGlyph(_ canvas: NSSize, color: NSColor? = nil) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            let side = min(rect.width, rect.height, 15), line = max(side / 13, 0.9)
            let box = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            (color ?? .black).set()
            let circle = NSBezierPath(ovalIn: box.insetBy(dx: line / 2 + 0.25, dy: line / 2 + 0.25)); circle.lineWidth = line; circle.stroke()
            let arrow = NSBezierPath(); arrow.lineWidth = line * 1.25; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            let tip = box.minY + side * 0.74, wing = side * 0.2
            arrow.move(to: NSPoint(x: box.midX, y: box.minY + side * 0.27)); arrow.line(to: NSPoint(x: box.midX, y: tip))
            arrow.move(to: NSPoint(x: box.midX - wing, y: tip - wing)); arrow.line(to: NSPoint(x: box.midX, y: tip))
            arrow.line(to: NSPoint(x: box.midX + wing, y: tip - wing)); arrow.stroke()
            return true
        }
        image.isTemplate = color == nil; return image
    }
    @objc func changeTab(_ sender: NSButton) { selectTab(sender.tag) }
    func selectTab(_ index: Int) {
        guard tabPanels.indices.contains(index) else { return }
        selectedTab = index
        for (i, panel) in tabPanels.enumerated() {
            panel.isHidden = i != index; tabButtons[i].state = i == index ? .on : .off
            tabButtons[i].contentTintColor = i == index || (i == 3 && updates.available != nil) ? .controlAccentColor : .secondaryLabelColor
        }
    }
    @objc func showAbout() { showSettings(); selectTab(3) }
    @objc func checkForUpdates() { installer.clearStatus(); updates.check(force: true) }
    @objc func performUpdate() { if let release = updates.available { installer.start(release) } }
    func installPreparedUpdate(_ prepared: PreparedUpdate) {
        do {
            guard !engine.isUpdatingSettings else { throw UpdateFailure(String(localized: "설정을 적용하고 있습니다. 잠시 후 다시 시도해주세요.", comment: "About tab: update status when the downloaded update cannot restart gksdud because a settings change is still being applied.")) }
            optionInput.cancel()
            try engine.prepareForExit()
            try UpdateInstaller.launchHelper(prepared)
            preparedToRelaunch = true; stopKeyTap(); timer?.invalidate(); updateTimer?.invalidate()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: prepared.directory)
            installer.fail(error); repair()
        }
    }
    var supportURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GKSDUDSupportURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    @objc func openSupport() { if let url = supportURL { NSWorkspace.shared.open(url) } }
    @objc func openProject() { NSWorkspace.shared.open(URL(string: "https://github.com/codingnoye/gksdud")!) }
    func refreshUpdates() {
        let release = updates.available
        tabButtons.last?.image = release == nil ? tabGlyph("?") : updateGlyph(NSSize(width: 24, height: 20), color: .controlAccentColor)
        selectTab(selectedTab)
        tabButtons.last?.setAccessibilityLabel(tabAccessibilityLabel("gksdud", updateAvailable: release != nil))
        for entry in statusMenu.items where entry.action == #selector(showAbout) { entry.isHidden = release == nil }
        let latest = release.map { " → v\($0.versionString)" } ?? ""
        updateHeading.stringValue = "v\(updates.installedVersion)\(latest)"
        updateSummary.string = release?.summary ?? ""
        updateScroll.isHidden = release == nil
        updateButton.isHidden = release == nil
        updateButton.isEnabled = !installer.busy
        checkUpdateButton.isEnabled = !updates.checking && !installer.busy
        if !installer.status.isEmpty { updateStatus.stringValue = installer.status }
        else if updates.checking { updateStatus.stringValue = String(localized: "업데이트 확인 중…", comment: "About tab: update status while checking for a new version.") }
        else if let error = updates.error { updateStatus.stringValue = error }
        else if let date = updates.lastChecked {
            updateStatus.stringValue = String(localized: "마지막 확인 \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))", comment: "About tab: update status after a check. %@ is the date and time of the last successful check, formatted for the user's region.")
        } else { updateStatus.stringValue = "" }
    }
    // One format for every tab, with the title as the argument, so the About tab keeps its brand title.
    func tabAccessibilityLabel(_ title: String, updateAvailable: Bool = false) -> String {
        updateAvailable ? String(localized: "\(title) 탭, 업데이트 가능", comment: "Settings window: accessibility label of the About tab button while an update is available. %@ is the tab title, gksdud.")
            : String(localized: "\(title) 탭", comment: "Settings window: accessibility label of a tab button. %@ is the tab title, such as General or gksdud.")
    }
}
