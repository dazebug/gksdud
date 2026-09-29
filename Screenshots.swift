import AppKit

// --capture-screenshots: the README images of the preview fixture. The settings window and the status menu are captured on screen
// and the badge strip is drawn offscreen. The user's own gksdud runs beside this with the same bundle ID, so the latch is locked,
// nothing creates a status item or an event tap, the windows ignore the mouse, an inactive or grown settings window and a menu
// that does not fit on its backdrop, has another app's window over it or the pointer on it stop the capture, and the fixture's
// tripwires run afterwards. The directory gets the five files only when all of them and the tripwires pass.

struct CaptureFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// Stable names, so the READMEs can show them before they are captured.
let screenshotNames = ["settings-general.png", "settings-caps.png", "settings-symbols.png", "menu.png", "badges.png"]

func captureScreenshots(to directory: URL, appearance: NSAppearance.Name) throws {
    SystemAccess.lock()
    // A hung capture or menu must not leave windows on the user's screen, nor a screencapture child to capture it once they are gone.
    // It is armed before the first call that can block.
    DispatchQueue.global().asyncAfter(deadline: .now() + 60) { CaptureChild.terminate(); fputs("FAIL: screenshots: still running after 60 s\n", stderr); exit(2) }
    // finishLaunching can activate this app, so the app to return to is read before it, and every failure after this returns to it.
    let previous = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == getpid() ? nil : $0 }
    defer { _ = previous?.activate(options: []) }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    NSApp.appearance = NSAppearance(named: appearance)
    guard CGPreflightScreenCaptureAccess() else { throw CaptureFailure("Grant Screen Recording to the terminal that runs this command (System Settings → Privacy & Security), then run it again.") }
    // The display with the menu bar starts the global coordinates at 0,0, so the menu's rectangle for -R never goes negative there.
    guard let screen = NSScreen.screens.first else { throw CaptureFailure("there is no display to capture") }
    if screen.backingScaleFactor < 2 { fputs("warning: the display with the menu bar has scale \(screen.backingScaleFactor), so the screenshots are smaller than the README's 2x images\n", stderr) }
    // A new folder each run, so a file from an earlier run cannot pass for this one, and the directory changes only when all five pass.
    let staging = URL(fileURLWithPath: "/private/tmp/gksdud-capture-\(getpid())-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    ScratchDefaults.removeAtExit(staging)
    defer { try? FileManager.default.removeItem(at: staging) }
    let files = screenshotNames.map { staging.appendingPathComponent($0) }
    let fixture = try PreviewFixture(uiLanguage: AppLanguage.current, state: .capture, resolveNames: true)
    defer { fixture.close() }
    let delegate = fixture.delegate, window = delegate.window!
    func settle(_ seconds: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }

    // A window capture includes the title bar; -o leaves out the shadow.
    window.ignoresMouseEvents = true; window.isRestorable = false; window.animationBehavior = .none
    window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    settle(0.3)
    for (tab, file) in zip(0..<3, files) {
        delegate.selectTab(tab); window.makeFirstResponder(nil); settle(0.3)
        if let problem = captureWindowProblem(active: NSApp.isActive, key: window.isKeyWindow, size: window.contentView!.frame.size, built: fixture.settingsSize) { throw CaptureFailure(problem) }
        try screencapture(["-x", "-o", "-l\(window.windowNumber)"], to: file)
    }
    window.orderOut(nil)

    // A pop-up menu captured by its window comes out grey, so the menu opens over an opaque backdrop of ours, on the half of the
    // screen away from the pointer, and the screen rectangle around it is captured if it lies on the backdrop.
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
            // The backdrop's bounds as the window server has them, in the coordinates of -R.
            let number = CGWindowID(backdrop.windowNumber)
            let listed = CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]] ?? []
            guard let placed = listed.first(where: { $0[kCGWindowIsOnscreen as String] as? Bool == true }) else { throw CaptureFailure("the backdrop, window \(number), is not on screen") }
            let above = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, number) as? [[String: Any]] ?? []
            let rect = try menuCaptureRect(windowsAbove: above, process: getpid(), backdrop: windowBounds(placed))
            // CGEvent's location has the top-left origin of the window list; the menu itself is the capture area less its margin.
            let hovering = { menuHoverProblem(highlighted: menu.highlightedItem?.title, pointer: CGEvent(source: nil)?.location, menu: rect.insetBy(dx: 12, dy: 12)) }
            if let problem = hovering() { throw CaptureFailure(problem) }
            try screencapture(["-x", "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"], to: files[3])
            if let problem = hovering() { throw CaptureFailure(problem) }
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
    let untouched = fixture.verifyUntouched()
    guard untouched.isEmpty else { throw CaptureFailure(untouched.joined(separator: "; ")) }
    try publishScreenshots(from: staging, to: directory, names: screenshotNames).forEach { print($0) }
}

// The exit status does not tell a blank capture from a real one, so the file is checked as well.
func screencapture(_ arguments: [String], to file: URL) throws {
    let process = Process(), command = (["screencapture"] + arguments + [file.lastPathComponent]).joined(separator: " ")
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); process.arguments = arguments + [file.path]
    try CaptureChild.run(process, command: command)
    do { _ = try screenshotPixels(file) } catch { throw CaptureFailure("\(command) finished, but \(error.localizedDescription)") }
}

// Every screencapture runs as a recorded child with a deadline. The watchdog's exit(2) runs no cleanup and leaves children running,
// reparented, so a stalled -R capture could take the screen once the backdrop is gone.
enum CaptureChild {
    private static let lock = NSLock()
    private static var child: Process?, stopped = false
    static var running: Process? { lock.lock(); defer { lock.unlock() }; return child }

    // Throws, naming the command, when the child fails or is killed. One still running at the deadline gets SIGTERM, then SIGKILL a
    // second later, and has ended before this throws, so the capture's own cleanup follows.
    static func run(_ process: Process, command: String, deadline: TimeInterval = 15) throws {
        let output = Pipe()
        process.standardOutput = output; process.standardError = output
        lock.lock()
        // A child started after the watchdog's terminate would outlive its exit.
        guard !stopped else { lock.unlock(); throw CaptureFailure("\(command) was not started, because the capture is stopping") }
        do { try process.run() } catch { lock.unlock(); throw error }
        child = process
        lock.unlock()
        defer { lock.lock(); child = nil; lock.unlock() }
        let end = ProcessInfo.processInfo.systemUptime + deadline
        while process.isRunning, ProcessInfo.processInfo.systemUptime < end { pump() }
        if process.isRunning {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning, ProcessInfo.processInfo.systemUptime < grace { pump() }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw CaptureFailure("\(command) did not finish within \(String(format: "%g", deadline)) s and was stopped")
        }
        process.waitUntilExit()
        // Read once the child has ended, so no read waits past the deadline.
        let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationReason == .exit else { throw CaptureFailure("\(command) was ended by signal \(process.terminationStatus)") }
        guard process.terminationStatus == 0 else { throw CaptureFailure("\(command) exited with status \(process.terminationStatus)\(message.isEmpty ? "" : ": \(message)")") }
    }

    // The watchdog's first step, from its own queue: SIGKILL the running child, wait briefly for it to end, and let no other start.
    static func terminate() {
        lock.lock(); stopped = true; let process = child; lock.unlock()
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        let end = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning, ProcessInfo.processInfo.systemUptime < end { usleep(10_000) }
    }
    private static func pump() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
}

// Moves the staged screenshots into the directory only when every one of them passes, so a failed capture keeps the previous set.
// Returns the published files' pixel sizes.
func publishScreenshots(from staging: URL, to directory: URL, names: [String]) throws -> [String] {
    let fm = FileManager.default
    var sizes: [String] = [], problems: [String] = []
    for name in names {
        do { let pixels = try screenshotPixels(staging.appendingPathComponent(name)); sizes.append("\(directory.appendingPathComponent(name).path): \(pixels.width)×\(pixels.height)") }
        catch { problems.append(error.localizedDescription) }
    }
    guard problems.isEmpty else { throw CaptureFailure("\(problems.joined(separator: "; ")); \(directory.path) keeps its previous screenshots") }
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    for name in names {
        let file = directory.appendingPathComponent(name), staged = staging.appendingPathComponent(name)
        if fm.fileExists(atPath: file.path) { _ = try fm.replaceItemAt(file, withItemAt: staged) } else { try fm.moveItem(at: staged, to: file) }
    }
    return sizes
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
// found among the windows above the backdrop, plus a 12 pt margin, in the whole points -R takes. -R captures whatever is on screen
// and the list holds only the windows above the backdrop, so the rectangle must lie on the backdrop, and a visible window of another
// process over it stops the capture instead of being captured with the menu.
func menuCaptureRect(windowsAbove windows: [[String: Any]], process: pid_t, backdrop: CGRect) throws -> CGRect {
    func number(_ window: [String: Any], _ key: CFString) -> NSNumber? { window[key as String] as? NSNumber }
    func visible(_ window: [String: Any]) -> Bool { (number(window, kCGWindowAlpha)?.doubleValue ?? 1) > 0 && !windowBounds(window).isEmpty }
    func describe(_ window: [String: Any]) -> String {
        let name = (window[kCGWindowName as String] as? String).map { " \"\($0)\"" } ?? ""
        return "\(window[kCGWindowOwnerName as String] as? String ?? "an unnamed process") (pid \(number(window, kCGWindowOwnerPID)?.intValue ?? 0))\(name) at layer \(number(window, kCGWindowLayer)?.intValue ?? 0), \(windowBounds(window))"
    }
    let ours = windows.filter { number($0, kCGWindowOwnerPID)?.int32Value == process && visible($0) }
    let menus = ours.filter { (number($0, kCGWindowLayer)?.int32Value ?? 0) >= CGWindowLevelForKey(.popUpMenuWindow) }
    guard !menus.isEmpty else {
        throw CaptureFailure("the status menu is not on screen: no window of this process at the pop-up menu layer \(CGWindowLevelForKey(.popUpMenuWindow)) is above the backdrop. Windows above it: \(windows.isEmpty ? "none" : windows.map(describe).joined(separator: "; "))")
    }
    let rect = menus.map(windowBounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -12, dy: -12).integral
    guard backdrop.contains(rect) else { throw CaptureFailure("the menu does not fit on the backdrop: its capture area \(rect) reaches past the backdrop \(backdrop), where the windows below would be captured") }
    let covering = windows.filter { number($0, kCGWindowOwnerPID)?.int32Value != process && visible($0) && windowBounds($0).intersects(rect) }
    guard covering.isEmpty else { throw CaptureFailure("\(covering.map(describe).joined(separator: "; ")) is over the menu's capture area \(rect); move or close it and run again") }
    return rect
}

// Activation can be refused, and an inactive app or a window that is not key draws grey controls. Content that needs more room
// grows the window past the size it was built with, which the README's 768 px images assume.
func captureWindowProblem(active: Bool, key: Bool, size: NSSize, built: NSSize) -> String? {
    var problems: [String] = []
    if !active { problems.append("the capture is not the active app, so the settings window would show inactive controls; run it again without switching apps") }
    if !key { problems.append("the settings window is not the key window, so its controls would show inactive; run the capture again without clicking") }
    if size.width > built.width + 1 || size.height > built.height + 1 {
        problems.append("the settings window's content grew from its built \(built.width)×\(built.height) pt to \(size.width)×\(size.height) pt, so a label needs more room than the window has")
    }
    return problems.isEmpty ? nil : problems.joined(separator: "; ")
}

func windowBounds(_ window: [String: Any]) -> CGRect { (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .null }

// The menu tracks the pointer even though the backdrop and the settings window ignore it, so a hovered row would be captured
// highlighted; a pointer that has just reached the menu may not have highlighted its row yet. There is no retry.
func menuHoverProblem(highlighted: String?, pointer: CGPoint?, menu: CGRect) -> String? {
    let again = "keep the pointer off the menu and run the capture again"
    if let highlighted { return "the menu item \"\(highlighted)\" is highlighted; \(again)" }
    if let pointer, menu.contains(pointer) { return "the pointer is on the menu at \(pointer); \(again)" }
    return nil
}

// The half of the screen away from the pointer, so the menu opens without an item highlighted under it.
func backdropFrame(_ screen: NSRect, pointer: NSPoint) -> NSRect {
    var half = screen
    half.size.width /= 2
    if pointer.x < screen.midX { half.origin.x = screen.midX }
    return half
}

struct BadgeStripRow { let text: NSAttributedString; let badges: [InputBadge] }

// Each icon style's title with its primary and English badges, then each of the primary language's glyphs: its own glyph, then its
// mode glyphs in registry order. A glyph row is named after an installed source that shows the glyph. A mode glyph that no installed
// source shows is left out, and the language's own glyph then takes the language's name.
func badgeStripRows(primary: InputLanguage, installed: [InputSource]) -> [BadgeStripRow] {
    let font = NSFont.systemFont(ofSize: 13), sources = installed.filter { InputLanguage.match($0.language) == primary }.sorted { $0.id < $1.id }
    return IconStyle.allCases.map { BadgeStripRow(text: AppDelegate.iconStyleTitle($0, primary: primary, font: font), badges: [$0.badge(for: primary), $0.badge(for: .english)]) }
        + primary.glyphs.compactMap { glyph in
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
