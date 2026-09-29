import Foundation

// Test, preview and capture modes run beside the user's own gksdud (same bundle ID). Every real
// macOS mutation checks this latch first, so a stray path fails instead of changing the live setup.
enum SystemAccess {
    struct Denied: LocalizedError { let action: String; var errorDescription: String? { "\(action) is disabled in this test mode" } }
    private(set) static var isLocked = false
    private(set) static var denied: [String] = []
    static func lock() { isLocked = true }   // deliberately no unlock
    static func permits(_ action: String) -> Bool { if isLocked { denied.append(action) }; return !isLocked }
    static func check(_ action: String) throws { guard permits(action) else { throw Denied(action: action) } }
}

// The one mode a launch runs, read from all of its arguments before anything starts. A malformed, unknown or conflicting argument
// gives usage instead of the normal app, which applies the live shortcut, Input menu and key mappings beside the user's own gksdud.
enum LaunchMode: Equatable {
    case app(showSettings: Bool), installUpdate, renderKeyboardUI(directory: String), probeOptionInput, localizationTest(language: String, strict: Bool)
    case captureScreenshots(directory: String, dark: Bool), selfTest, integrationTest, usage(reason: String)
    // Info.plist's GKSDUDLaunchModes, which scripts/capture-screenshots.sh reads without running the app, because an older build starts
    // normally on arguments it does not know. Bump it with Info.plist and the script when the walk or capture arguments change.
    static let contract = 1
    static let usageText = """
        Usage: gksdud [--settings]
               gksdud --self-test
               gksdud --localization-test <language> [--strict]
               gksdud --render-keyboard-ui <directory>
               gksdud --capture-screenshots <directory> [--appearance light|dark]
               gksdud --probe-option-input
               gksdud --integration-test
        Arguments with a single dash, such as -AppleLanguages '(ja)', are left to macOS.
        """
    // Each mode flag, and whether it takes a value.
    private static let modes = ["--self-test": false, "--localization-test": true, "--render-keyboard-ui": true, "--capture-screenshots": true,
                                "--probe-option-input": false, "--integration-test": false]
    // Each option, the mode it belongs to ("" is the normal app), and whether it takes a value.
    private static let options: [(flag: String, mode: String, takesValue: Bool)] = [("--strict", "--localization-test", false), ("--appearance", "--capture-screenshots", true), ("--settings", "", false)]

    // The arguments after the executable.
    init(arguments: [String]) {
        // The updater's helper; runHelper checks its operands.
        if arguments.first == "--install-update" { self = .installUpdate; return }
        var rest = arguments[...], mode: String?, given: [String: String] = [:]
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--") else {
                guard argument.hasPrefix("-") else { self = .usage(reason: "unexpected argument \(argument)"); return }
                // macOS's own: NSArgumentDomain pairs such as -AppleLanguages '(ko)', and the lone -psn_0_… of a quarantined app's first
                // launch. Their value never starts with -, so no mode flag can hide behind them.
                if let value = rest.first, !value.hasPrefix("-") { rest.removeFirst() }
                continue
            }
            guard let takesValue = Self.modes[argument] ?? Self.options.first(where: { $0.flag == argument })?.takesValue else {
                self = .usage(reason: argument == "--install-update" ? "--install-update must be the first argument" : "unknown argument \(argument)"); return
            }
            guard given[argument] == nil else { self = .usage(reason: "\(argument) is given twice"); return }
            if Self.modes[argument] != nil {
                if let mode { self = .usage(reason: "\(mode) and \(argument) are two modes; give one"); return }
                mode = argument
            }
            var value = ""
            if takesValue {
                guard let next = rest.first, !next.isEmpty, !next.hasPrefix("-") else { self = .usage(reason: "\(argument) needs a value"); return }
                value = rest.removeFirst()
            }
            given[argument] = value
        }
        for option in Self.options where given[option.flag] != nil && option.mode != (mode ?? "") {
            self = .usage(reason: "\(option.flag) belongs to \(option.mode.isEmpty ? "the normal app, without a mode" : option.mode)"); return
        }
        let appearance = given["--appearance"] ?? "light"
        guard appearance == "light" || appearance == "dark" else { self = .usage(reason: "--appearance takes light or dark, not \(appearance)"); return }
        switch mode {
        case nil: self = .app(showSettings: given["--settings"] != nil)
        case "--self-test": self = .selfTest
        case "--localization-test": self = .localizationTest(language: given["--localization-test"]!, strict: given["--strict"] != nil)
        case "--render-keyboard-ui": self = .renderKeyboardUI(directory: given["--render-keyboard-ui"]!)
        case "--capture-screenshots": self = .captureScreenshots(directory: given["--capture-screenshots"]!, dark: appearance == "dark")
        case "--probe-option-input": self = .probeOptionInput
        case "--integration-test": self = .integrationTest
        case let unhandled?: self = .usage(reason: "\(unhandled) has no mode")
        }
    }
    // Test and capture modes run beside the user's own gksdud, and usage runs nothing. The app, the updater and the two deliberate
    // live-system tests change the real setup.
    var locksSystemAccess: Bool {
        switch self {
        case .app, .installUpdate, .probeOptionInput, .integrationTest: return false
        case .selfTest, .localizationTest, .renderKeyboardUI, .captureScreenshots, .usage: return true
        }
    }
}
