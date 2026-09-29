import AppKit

// Real TIS IDs, mode IDs and English names. Tests and previews use them instead of the enabled list,
// because automation must never enable or select a real input source.
enum SampleSource {
    static let abc = InputSource(id: "com.apple.keylayout.ABC", language: "en", name: "ABC")
    static let twoSet = InputSource(id: "com.apple.inputmethod.Korean.2SetKorean", language: "ko", mode: "com.apple.inputmethod.Korean.2SetKorean", name: "2-Set Korean", methodName: "Korean")
    // Kotoeri's Romaji and Kana typing share the Hiragana mode ID and name.
    static let hiragana = InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", language: "ja", mode: "com.apple.inputmethod.Japanese", name: "Hiragana", methodName: "Japanese – Romaji")
    static let kanaHiragana = InputSource(id: "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese", language: "ja", mode: "com.apple.inputmethod.Japanese", name: "Hiragana", methodName: "Japanese – Kana")
    static let katakana = InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana", language: "ja", mode: "com.apple.inputmethod.Japanese.Katakana", name: "Katakana", methodName: "Japanese – Romaji")
    // Kotoeri's Romaji mode reports English and is ASCII-capable.
    static let romaji = InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", language: "en", mode: "com.apple.inputmethod.Roman", name: "Romaji", methodName: "Japanese – Romaji")
    static let zhuyin = InputSource(id: "com.apple.inputmethod.TCIM.Zhuyin", language: "zh-Hant", mode: "com.apple.inputmethod.TCIM.Zhuyin", name: "Zhuyin – Traditional", methodName: "Chinese, Traditional")
    static let cangjie = InputSource(id: "com.apple.inputmethod.TCIM.Cangjie", language: "zh-Hant", mode: "com.apple.inputmethod.TCIM.Cangjie", name: "Cangjie – Traditional", methodName: "Chinese, Traditional")
    static let cantonesePhonetic = InputSource(id: "com.apple.inputmethod.TYIM.Phonetic", language: "yue-Hant", mode: "com.apple.inputmethod.TYIM.Phonetic", name: "Phonetic – Cantonese", methodName: "Cantonese, Traditional")
    static let simplifiedPinyin = InputSource(id: "com.apple.inputmethod.SCIM.ITABC", language: "zh-Hans", mode: "com.apple.inputmethod.SCIM.ITABC", name: "Pinyin – Simplified", methodName: "Chinese, Simplified")
    static let ainu = InputSource(id: "com.apple.inputmethod.AinuIM.Ainu", language: "ain", mode: "com.apple.AinuIM.Ainu", name: "Ainu", methodName: "Ainu")
    static let konkani = InputSource(id: "com.apple.keylayout.Konkani", language: "kok", name: "Konkani – InScript")
}

// Stands in for InputSources.system: select only records the ID and updates current; it never calls TIS.
final class FakeInputSources {
    var current: InputSource?
    var enabled: [InputSource]
    private(set) var selected: [String] = []
    init(_ enabled: [InputSource], current: InputSource? = nil) { self.enabled = enabled; self.current = current ?? enabled.first }
    var inputSources: InputSources {
        InputSources(current: { self.current }, enabled: { self.enabled }, select: { id in
            self.selected.append(id)
            guard let source = self.enabled.first(where: { $0.id == id }) else { return false }
            self.current = source; return true
        })
    }
}

// The enabled input sources each UI language's previews show, the first one current. Every UI language needs a scene.
enum PreviewScene {
    static let sources: [String: [InputSource]] = ["ko": [SampleSource.twoSet, SampleSource.abc],
        "ja": [SampleSource.hiragana, SampleSource.katakana, SampleSource.abc], "zh-Hant": [SampleSource.zhuyin, SampleSource.cangjie, SampleSource.abc]]
    // Installed names follow the UI language and are found even while their input method is disabled; unit tests keep the English names.
    static func named(_ source: InputSource) -> InputSource { var named = source; named.name = InputSources.installed(id: source.id)?.name ?? source.name; return named }
}

// What a preview shows. The localization walk visits several states and screenshots use one.
struct PreviewState {
    var trusted = true            // faked accessibility permission
    var updateAvailable = false   // a cached release newer than this build
    var keyboardWarning = false   // one keyboard keeps failing and another is disconnected
    var longPressFailure = false  // the long-press checkbox tooltip shows the failure message
    var keyboardDefault = true    // keyboards without their own choice are remapped
    var longPress = false         // the opt-in long-press checkbox is on
    // The README screenshots: every other setting keeps its first-launch default, and there is no update or warning.
    static let capture = PreviewState(longPress: true)
}

// A read-only look at the two system settings gksdud changes: the Input menu and the "Select the previous input source" shortcut.
struct SystemSnapshot: Equatable {
    let inputMenu: NSObject?, shortcut: NSObject?
    init() {
        func read(_ key: String, _ domain: String) -> NSObject? { CFPreferencesAppSynchronize(domain as CFString); return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSObject }
        inputMenu = read("visible", "com.apple.TextInputMenu")
        shortcut = (read("AppleSymbolicHotKeys", "com.apple.symbolichotkeys") as? NSDictionary)?["60"] as? NSObject
    }
}

// The defaults suites of tests, previews and captures. A named suite keeps its plist in ~/Library/Preferences even after
// removePersistentDomain, so each suite is a plist path in a gksdud- folder in /private/tmp: by default this process's
// folder, which exit removes.
final class ScratchDefaults {
    let path: String, defaults: UserDefaults
    // Pass a folder of your own for state that must outlive a failed run; exit leaves it alone.
    init(_ label: String, in folder: URL = ScratchDefaults.folder) {
        precondition(Self.isScratchFolder(folder), "defaults suites belong in a gksdud- folder in /private/tmp or the temporary directory, not \(folder.path)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        path = folder.appendingPathComponent("\(label)-\(UUID().uuidString)").path; defaults = Self.open(path)
    }
    // A second instance on the same file, as a relaunch reads it.
    func reopen() -> UserDefaults { Self.open(path) }
    // removePersistentDomain empties the domain but leaves its file.
    func close() { defaults.removePersistentDomain(forName: path); try? FileManager.default.removeItem(atPath: path + ".plist") }
    private static func open(_ path: String) -> UserDefaults { UserDefaults(suiteName: path)! } // build.sh: the only named suite

    // /private/tmp/gksdud-defaults-<pid>-<UUID>, made on first use.
    static let folder: URL = {
        removeDeadFolders()
        let folder = URL(fileURLWithPath: "/private/tmp/gksdud-defaults-\(getpid())-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        removeAtExit(folder)
        return folder
    }()
    private static let lock = NSLock()
    private static var exitFolders: [URL] = []
    // atexit takes a C function, which cannot capture, so the one hook reads the folders from exitFolders.
    private static let exitHook: Void = { _ = atexit { ScratchDefaults.removeExitFolders() } }()
    // Removes the folder when the process exits, also through exit(1) in featureCheck or a catch block and the capture watchdog's exit(2).
    static func removeAtExit(_ folder: URL) {
        precondition(isScratchFolder(folder), "only a gksdud- folder in /private/tmp or the temporary directory can be removed at exit, not \(folder.path)")
        _ = exitHook
        lock.lock(); exitFolders.append(folder); lock.unlock()
    }
    private static func removeExitFolders() {
        lock.lock(); let folders = exitFolders; exitFolders.removeAll(); lock.unlock()
        for folder in folders where isScratchFolder(folder) { try? FileManager.default.removeItem(at: folder) }
    }
    // A gksdud- folder directly in /private/tmp or the temporary directory, the only kind this ever removes.
    static func isScratchFolder(_ folder: URL) -> Bool {
        func resolved(_ path: String) -> String? {
            guard let real = realpath(path, nil) else { return nil }
            defer { free(real) }
            return String(cString: real)
        }
        guard folder.lastPathComponent.hasPrefix("gksdud-"), let parent = resolved(folder.deletingLastPathComponent().path) else { return false }
        return parent == resolved("/private/tmp") || parent == resolved(NSTemporaryDirectory())
    }
    // Precondition traps skip atexit, so the first suite of a run removes the defaults folders of processes that no longer exist.
    // Only the exact name gksdud-defaults-<pid>-<UUID> is matched.
    static func removeDeadFolders(in directory: String = "/private/tmp") {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where name.hasPrefix("gksdud-defaults-") {
            let parts = name.dropFirst("gksdud-defaults-".count).split(separator: "-", maxSplits: 1).map(String.init)
            guard parts.count == 2, let pid = pid_t(parts[0]), pid > 0, String(pid) == parts[0], UUID(uuidString: parts[1])?.uuidString == parts[1],
                  kill(pid, 0) == -1, errno == ESRCH else { continue }
            try? FileManager.default.removeItem(atPath: (directory as NSString).appendingPathComponent(name))
        }
    }
}

// The settings window, keyboard sheet, status menu and main menu on fakes, for tests, the localization walk and screenshots.
// It never calls applicationDidFinishLaunching, updateMenu (so there is no status item), repair, ensureKeyTap or updates.check,
// and the fakes record every attempt to change the system instead of making it.
final class PreviewFixture {
    // The fakes' closures exist before the fixture does, so they share this instead of self.
    final class Recorder { var trusted = true; var violations: [String] = [] }
    let delegate: AppDelegate, inputs: FakeInputSources, scratch: ScratchDefaults, defaults: UserDefaults, recorder: Recorder
    let keyboardSettings: KeyboardSettingsController, mainMenu: NSMenu
    // The content sizes the windows are built with, read before any layout. Text resists compression more than a window
    // keeps its size, so content that needs more room grows the window when it is laid out instead of clipping.
    let settingsSize: NSSize, sheetSize: NSSize
    private let before = SystemSnapshot(), deniedBefore = SystemAccess.denied.count
    init(uiLanguage: String, state: PreviewState = PreviewState(), resolveNames: Bool = false) throws {
        guard let scene = PreviewScene.sources[uiLanguage] else { throw NSError(domain: "preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "No preview scene for \(uiLanguage)"]) }
        let scratch = ScratchDefaults("preview"), defaults = scratch.defaults
        let recorder = Recorder(), inputs = FakeInputSources(resolveNames ? scene.map(PreviewScene.named) : scene)
        recorder.trusted = state.trusted
        func refuse(_ action: String) -> Error { recorder.violations.append(action); return SystemAccess.Denied(action: action) }
        let builtIn = TestKeyboard("preview-builtin", name: "Apple Internal Keyboard / Trackpad", serial: "builtin")
        let virtual = TestKeyboard("preview-virtual", name: "Karabiner DriverKit VirtualHIDKeyboard 1.8.0", serial: "virtual")
        let wireless = TestKeyboard("preview-wireless", name: "SP109 Wireless Keyboard", serial: "wireless")
        var devices: [KeyboardDevice] = [builtIn, virtual, wireless]
        let engine = Engine(defaults: defaults, discover: { devices }, shortcutPreferences: ShortcutPreferences(read: { [:] },
            write: { _ in throw refuse("shortcut write") }, activate: { throw refuse("shortcut activation") }))
        if !state.keyboardDefault { engine.keyboards.defaultEnabled = false }
        if state.longPress { defaults.set(true, forKey: "longPressCapsLock") }
        engine.keyboards.reconcile(source: engine.source, target: engine.target.usage, active: true)
        if state.keyboardWarning {
            // Three failed writes raise the warning; the wireless keyboard stays known but disconnected.
            devices = [builtIn, virtual]; virtual.mappings = []; virtual.failWrite = true
            for _ in 0..<3 { engine.keyboards.reconcile(source: engine.source, target: engine.target.usage, active: true) }
        }
        defaults.set(Date(timeIntervalSince1970: 1_800_000_000), forKey: "updates.lastSuccess")
        if state.updateAvailable {
            // The About tab shows only the release notes' summary section, found by its heading.
            let release = AppRelease(tag_name: "v99.0.0", html_url: "https://github.com/codingnoye/gksdud/releases/tag/v99.0.0", body: "## \(AppRelease.summaryHeading)\n- v99.0.0", draft: false, prerelease: false)
            defaults.set(try JSONEncoder().encode(release), forKey: "updates.release")
        }
        let delegate = AppDelegate(engine: engine, environment: AppDelegate.Environment(inputSources: inputs.inputSources, accessibilityTrusted: { recorder.trusted },
            capsLock: { _ in throw refuse("Caps Lock change") }, loginItemStatus: { .notRegistered }, setLoginItem: { _ in throw refuse("login item change") }))
        delegate.updates = UpdateChecker(defaults: defaults, fetch: { _, _ in recorder.violations.append("update request") })
        delegate.buildWindow()
        let keyboardSettings = KeyboardSettingsController(manager: engine.keyboards) { [weak delegate] in delegate?.refreshKeyboardState() }
        delegate.keyboardSettings = keyboardSettings
        settingsSize = delegate.window.contentView!.frame.size; sheetSize = keyboardSettings.window.contentView!.frame.size
        // The status line the app fills in its launch repair; repair itself would reach the event tap and the shortcut.
        delegate.refreshStatus()
        if state.longPressFailure, let current = inputs.current { delegate.showLongPressError(delegate.longPressFailureMessage(for: current)) }
        delegate.menuNeedsUpdate(delegate.statusMenu); delegate.menuWillOpen(delegate.statusMenu)
        self.delegate = delegate; self.inputs = inputs; self.scratch = scratch; self.defaults = defaults; self.recorder = recorder
        self.keyboardSettings = keyboardSettings; mainMenu = delegate.buildMainMenu()
    }
    // What reached, or tried to reach, the live system; empty when the preview left it alone.
    func verifyUntouched() -> [String] {
        var problems = recorder.violations.map { "a fake was asked for: \($0)" } + SystemAccess.denied.dropFirst(deniedBefore).map { "blocked: \($0)" }
        if delegate.keyTap != nil { problems.append("an event tap exists") }
        // A status item would put a second gksdud icon in the user's menu bar.
        if delegate.item != nil { problems.append("a status item exists") }
        // Engine writes these undo keys before it changes the shortcut or the Input menu.
        problems += ["shortcutBackedUp", "inputMenuBackedUp"].filter { defaults.object(forKey: $0) != nil }.map { "the preview suite holds \($0)" }
        if SystemSnapshot() != before { problems.append("the Input menu or the input source shortcut changed") }
        return problems
    }
    func close() {
        delegate.menuDidClose(delegate.statusMenu)
        keyboardSettings.window.close(); delegate.window.close()
        scratch.close()
    }
}
