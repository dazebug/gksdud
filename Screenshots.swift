import AppKit

// --capture-screenshots: the README images of the preview fixture. The settings window and the status menu are captured on screen
// and the badge strip is drawn offscreen. The user's own gksdud runs beside this with the same bundle ID, so the latch is locked,
// nothing creates a status item or an event tap, the windows ignore the mouse, another app's window over the menu stops the
// capture, and the fixture's tripwires run afterwards.

struct CaptureFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// Stable names, so the READMEs can show them before they are captured.
let screenshotNames = ["settings-general.png", "settings-caps.png", "settings-symbols.png", "menu.png", "badges.png"]

func captureScreenshots(to directory: URL, appearance: NSAppearance.Name) throws {
    SystemAccess.lock()
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    NSApp.appearance = NSAppearance(named: appearance)
    // A hung capture or menu must not leave windows on the user's screen.
    DispatchQueue.global().asyncAfter(deadline: .now() + 60) { fputs("FAIL: screenshots: still running after 60 s\n", stderr); exit(2) }
    guard CGPreflightScreenCaptureAccess() else { throw CaptureFailure("Grant Screen Recording to the terminal that runs this command (System Settings → Privacy & Security), then run it again.") }
    // The display with the menu bar starts the global coordinates at 0,0, so the menu's rectangle for -R never goes negative there.
    guard let screen = NSScreen.screens.first else { throw CaptureFailure("there is no display to capture") }
    let previous = NSWorkspace.shared.frontmostApplication
    if screen.backingScaleFactor < 2 { fputs("warning: the display with the menu bar has scale \(screen.backingScaleFactor), so the screenshots are smaller than the README's 2x images\n", stderr) }
    let files = screenshotNames.map { directory.appendingPathComponent($0) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // A file from an earlier run must not pass for this one.
    for file in files where FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    let fixture = try PreviewFixture(uiLanguage: AppLanguage.current, state: .capture, resolveNames: true)
    defer { fixture.close(); _ = previous?.activate(options: []) }
    let delegate = fixture.delegate, window = delegate.window!
    func settle(_ seconds: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }

    // A window capture includes the title bar; -o leaves out the shadow.
    window.ignoresMouseEvents = true; window.isRestorable = false; window.animationBehavior = .none
    window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    settle(0.3)
    for (tab, file) in zip(0..<3, files) {
        delegate.selectTab(tab); window.makeFirstResponder(nil); settle(0.3)
        try screencapture(["-x", "-o", "-l\(window.windowNumber)"], to: file)
    }
    window.orderOut(nil)

    // A pop-up menu captured by its window comes out grey, so the menu opens over an opaque backdrop of ours, on the half of the
    // screen away from the pointer, and the screen rectangle around it is captured.
    let backdrop = NSWindow(contentRect: backdropFrame(screen.visibleFrame, pointer: NSEvent.mouseLocation), styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.backgroundColor = .windowBackgroundColor; backdrop.ignoresMouseEvents = true; backdrop.isReleasedWhenClosed = false
    backdrop.isRestorable = false; backdrop.animationBehavior = .none
    backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    backdrop.orderFrontRegardless()
    defer { backdrop.orderOut(nil) }
    settle(0.3)
    let menu = delegate.statusMenu, content = backdrop.contentView!
    menu.appearance = NSAppearance(named: appearance)
    var captured: Result<Void, Error>?
    // popUp tracks the menu until it closes, so the capture runs from a timer in the common modes, which include menu tracking.
    let timer = Timer(timeInterval: 1, repeats: false) { _ in
        captured = Result {
            let above = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, CGWindowID(backdrop.windowNumber)) as? [[String: Any]] ?? []
            let rect = try menuCaptureRect(windowsAbove: above, process: getpid()).integral
            try screencapture(["-x", "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"], to: files[3])
        }
        menu.cancelTracking()
    }
    RunLoop.main.add(timer, forMode: .common)
    let size = menu.size, opened = Date()
    _ = menu.popUp(positioning: nil, at: NSPoint(x: (content.bounds.width - size.width) / 2, y: (content.bounds.height + size.height) / 2), in: content)
    timer.invalidate(); backdrop.orderOut(nil)
    guard let captured else {
        throw CaptureFailure(String(format: "the status menu closed after %.1f s, before its capture at 1 s; a click or key press during the capture closes it", Date().timeIntervalSince(opened)))
    }
    try captured.get()

    try renderBadgeStrip(primary: delegate.primaryLanguage(), appearance: appearance, to: files[4])
    var sizes: [String] = [], problems: [String] = []
    for file in files {
        do { let pixels = try screenshotPixels(file); sizes.append("\(file.path): \(pixels.width)×\(pixels.height)") } catch { problems.append(error.localizedDescription) }
    }
    problems += fixture.verifyUntouched()
    guard problems.isEmpty else { throw CaptureFailure(problems.joined(separator: "; ")) }
    sizes.forEach { print($0) }
}

// The exit status does not tell a blank capture from a real one, so the file is checked as well.
func screencapture(_ arguments: [String], to file: URL) throws {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); process.arguments = arguments + [file.path]
    process.standardOutput = output; process.standardError = output
    try process.run()
    let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    process.waitUntilExit()
    let command = (["screencapture"] + arguments + [file.lastPathComponent]).joined(separator: " ")
    guard process.terminationStatus == 0 else { throw CaptureFailure("\(command) exited with status \(process.terminationStatus)\(message.isEmpty ? "" : ": \(message)")") }
    do { _ = try screenshotPixels(file) } catch { throw CaptureFailure("\(command) finished, but \(error.localizedDescription)") }
}

// A screenshot's pixel size, or why it cannot be one: missing, empty, not an image, or a single colour, as a blank capture is.
func screenshotPixels(_ file: URL) throws -> (width: Int, height: Int) {
    guard let data = FileManager.default.contents(atPath: file.path) else { throw CaptureFailure("\(file.path) is missing") }
    guard !data.isEmpty else { throw CaptureFailure("\(file.path) is empty") }
    guard let image = NSBitmapImageRep(data: data)?.cgImage else { throw CaptureFailure("\(file.path) is not an image") }
    // One known pixel format, whatever the file's own format is.
    var pixels = [UInt32](repeating: 0, count: image.width * image.height)
    let drawn = pixels.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue).map { $0.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) } != nil
    }
    guard drawn else { throw CaptureFailure("\(file.path) cannot be read as pixels") }
    guard pixels.contains(where: { $0 != pixels[0] }) else { throw CaptureFailure("\(file.path) is a single uniform colour, as a blank capture is") }
    return (image.width, image.height)
}

// The rectangle for menu.png in the global top-left coordinates that CGWindowList and screencapture -R share: our menu window,
// found among the windows above the backdrop, plus a 12 pt margin. A visible window of another process there would be captured
// with the menu, so it stops the capture instead.
func menuCaptureRect(windowsAbove windows: [[String: Any]], process: pid_t) throws -> CGRect {
    func number(_ window: [String: Any], _ key: CFString) -> NSNumber? { window[key as String] as? NSNumber }
    func bounds(_ window: [String: Any]) -> CGRect { (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .null }
    func visible(_ window: [String: Any]) -> Bool { (number(window, kCGWindowAlpha)?.doubleValue ?? 1) > 0 && !bounds(window).isEmpty }
    func describe(_ window: [String: Any]) -> String {
        let name = (window[kCGWindowName as String] as? String).map { " \"\($0)\"" } ?? ""
        return "\(window[kCGWindowOwnerName as String] as? String ?? "an unnamed process") (pid \(number(window, kCGWindowOwnerPID)?.intValue ?? 0))\(name) at layer \(number(window, kCGWindowLayer)?.intValue ?? 0), \(bounds(window))"
    }
    let ours = windows.filter { number($0, kCGWindowOwnerPID)?.int32Value == process && visible($0) }
    let menus = ours.filter { (number($0, kCGWindowLayer)?.int32Value ?? 0) >= CGWindowLevelForKey(.popUpMenuWindow) }
    guard !menus.isEmpty else {
        throw CaptureFailure("the status menu is not on screen: no window of this process at the pop-up menu layer \(CGWindowLevelForKey(.popUpMenuWindow)) is above the backdrop. Windows above it: \(windows.isEmpty ? "none" : windows.map(describe).joined(separator: "; "))")
    }
    let rect = menus.map(bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -12, dy: -12)
    let covering = windows.filter { number($0, kCGWindowOwnerPID)?.int32Value != process && visible($0) && bounds($0).intersects(rect) }
    guard covering.isEmpty else { throw CaptureFailure("\(covering.map(describe).joined(separator: "; ")) is over the menu's capture area \(rect); move or close it and run again") }
    return rect
}

// The half of the screen away from the pointer, so the menu opens without an item highlighted under it.
func backdropFrame(_ screen: NSRect, pointer: NSPoint) -> NSRect {
    var half = screen
    half.size.width /= 2
    if pointer.x < screen.midX { half.origin.x = screen.midX }
    return half
}

struct BadgeStripRow { let text: NSAttributedString; let badges: [InputBadge] }

// Each icon style's title with its primary and English badges, then each glyph the primary language shows: its own glyph, then its
// mode glyphs in code point order (radical and stroke order for Han, gojūon order for kana). A glyph row is named after an installed
// source that shows the glyph. A mode glyph that no installed source shows is left out, and the language's own glyph then takes
// the language's name.
func badgeStripRows(primary: InputLanguage, installed: [InputSource]) -> [BadgeStripRow] {
    let font = NSFont.systemFont(ofSize: 13), sources = installed.filter { InputLanguage.match($0.language) == primary }.sorted { $0.id < $1.id }
    let glyphs = [primary.glyph] + Set(primary.modeGlyphs.values).subtracting([primary.glyph]).sorted()
    return IconStyle.allCases.map { BadgeStripRow(text: AppDelegate.iconStyleTitle($0, primary: primary, font: font), badges: [$0.badge(for: primary), $0.badge(for: .english)]) }
        + glyphs.compactMap { glyph in
            guard let name = sources.first(where: { primary.glyph(mode: $0.mode) == glyph })?.name ?? (glyph == primary.glyph ? primary.displayName : nil) else { return nil }
            return BadgeStripRow(text: NSAttributedString(string: name, attributes: [.font: font]), badges: [.text(glyph, filled: true, language: primary.id)])
        }
}

// The rows drawn offscreen at 2x in the label colour on the window background of the given appearance, so the self-test draws it too.
func renderBadgeStrip(primary: InputLanguage, appearance: NSAppearance.Name, to file: URL, installed: [InputSource] = InputSources.installed()) throws {
    let rows = badgeStripRows(primary: primary, installed: installed)
    let width: CGFloat = 360, row: CGFloat = 28, margin: CGFloat = 16, gap: CGFloat = 12, scale: CGFloat = 2
    let height = margin * 2 + row * CGFloat(rows.count) + gap
    guard let drawing = NSAppearance(named: appearance), let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureFailure("cannot draw \(file.lastPathComponent) in \(appearance.rawValue)") }
    context.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    drawing.performAsCurrentDrawingAppearance {
        NSColor.windowBackgroundColor.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        var top = height - margin
        for (index, content) in rows.enumerated() {
            if index == IconStyle.allCases.count { NSColor.separatorColor.setFill(); NSRect(x: margin, y: top - gap / 2, width: width - margin * 2, height: 1 / scale).fill(); top -= gap }
            top -= row
            // Badges are template images; the menu bar tints them, so the strip does too.
            for (column, badge) in content.badges.enumerated() {
                let frame = NSRect(x: margin + CGFloat(column) * 30, y: top + (row - 20) / 2, width: 22, height: 20)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                AppDelegate.badgeImage(badge).draw(in: frame)
                NSColor.labelColor.setFill(); frame.fill(using: .sourceAtop)
                context.endTransparencyLayer()
            }
            let text = NSMutableAttributedString(attributedString: content.text)
            text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: text.length))
            text.draw(at: NSPoint(x: margin + 68, y: top + (row - text.size().height) / 2))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CaptureFailure("cannot encode \(file.lastPathComponent) as PNG") }
    try data.write(to: file)
}
