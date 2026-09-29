import AppKit
import Carbon

// Preserve an actionable failure location in optimized CI builds, where Swift's
// precondition trap otherwise loses its message and buffered stdout.
func featureCheck(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else {
        fputs("FAIL: \(file):\(line) \(message)\n", stderr)
        exit(1)
    }
}

// Runs first in --self-test and checks where the suite lies before writing to it, because a named suite would leave its plist in ~/Library/Preferences.
func runScratchDefaultsTests() {
    let fm = FileManager.default, scratch = ScratchDefaults("scratch-test"), folder = ScratchDefaults.folder.path, file = scratch.path + ".plist"
    featureCheck((scratch.path as NSString).deletingLastPathComponent == folder && (folder as NSString).deletingLastPathComponent == "/private/tmp"
        && (folder as NSString).lastPathComponent.hasPrefix("gksdud-defaults-\(getpid())-"), "the suite \(scratch.path) must be in this process's folder in /private/tmp, \(folder)")
    scratch.defaults.set("value", forKey: "key")
    featureCheck(fm.fileExists(atPath: file), "a write must create \(file)")
    featureCheck(scratch.reopen().string(forKey: "key") == "value", "reopen() must read the value back")
    scratch.close()
    featureCheck(!fm.fileExists(atPath: file), "close() must delete \(file)")
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    guard let fixture = try? PreviewFixture(uiLanguage: "ko") else { featureCheck(false, "the ko preview fixture must build"); return }
    let fixtureFile = fixture.scratch.path + ".plist", written = fm.fileExists(atPath: fixtureFile)
    fixture.close()
    featureCheck(written && !fm.fileExists(atPath: fixtureFile), "PreviewFixture.close() must delete its suite file \(fixtureFile) (written: \(written))")
    let allowed = ["/private/tmp/gksdud-a", "/tmp/gksdud-a", NSTemporaryDirectory() + "gksdud-a"], refused = ["/private/tmp/other", folder + "/gksdud-a", "/Library/gksdud-a"]
    featureCheck(allowed.allSatisfy { ScratchDefaults.isScratchFolder(URL(fileURLWithPath: $0)) } && !refused.contains { ScratchDefaults.isScratchFolder(URL(fileURLWithPath: $0)) },
        "only gksdud- folders directly in /private/tmp or the temporary directory may be removed")
    // A process that has exited and been reaped gives a pid that no longer exists.
    let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    do { try child.run(); child.waitUntilExit() } catch { featureCheck(false, "/usr/bin/true must run: \(error)") }
    let sweep = folder + "/sweep", dead = "gksdud-defaults-\(child.processIdentifier)-\(UUID().uuidString)"
    let kept = ["gksdud-defaults-\(getpid())-\(UUID().uuidString)", "gksdud-defaults-\(child.processIdentifier)-\(UUID().uuidString.lowercased())", "gksdud-self-test-\(UUID().uuidString)"].sorted()
    for name in [dead] + kept { try? fm.createDirectory(atPath: sweep + "/" + name, withIntermediateDirectories: true) }
    ScratchDefaults.removeDeadFolders(in: sweep)
    let left = (try? fm.contentsOfDirectory(atPath: sweep).sorted()) ?? []
    featureCheck(left == kept, "the sweep must remove only \(dead), leaving \(kept); left \(left)")
    print("PASS: scratch defaults: suites in this process's /private/tmp folder, written there at once, read back by reopen, deleted by close and PreviewFixture.close; only gksdud- folders in /private/tmp or the temporary directory are removable, and the sweep takes only a dead process's defaults folder")
}

func runFeatureTests() {
    runSystemAccessTests()
    runLaunchModeTests()
    featureCheck(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.9")!)
    featureCheck(ReleaseVersion("1.2")! == ReleaseVersion("1.2.0")!)
    for invalid in ["pre-v1.3.0", "1.3.0-beta", "1..2", "1.2x", "", "1.2.99999999999999999999999"] { featureCheck(ReleaseVersion(invalid) == nil) }
    func release(_ body: String?, tag: String = "v1.3.0", url: String = "https://github.com/codingnoye/gksdud/releases/tag/v1.3.0", draft: Bool = false, pre: Bool = false) -> AppRelease {
        AppRelease(tag_name: tag, html_url: url, body: body, draft: draft, prerelease: pre)
    }
    let sample = release("### 요약\r\n\r\n- 탭 추가\r\n- 특수문자 개선\r\n\r\n### 설치\r\n이 내용은 표시하지 않습니다.")
    featureCheck(sample.summary.contains("탭 추가") && !sample.summary.contains("설치"))
    featureCheck(release("## 요약\n<!-- 게시 전 요약 작성 -->\n## 설치").summary == release(nil).summary)
    featureCheck(release("## 요약\n본문\n### 세부\n세부 내용\n## 설치\n비표시").summary == "본문\n### 세부\n세부 내용")
    featureCheck(release("**요약**\n본문\n## 설치\n비표시").summary == "본문")
    featureCheck(release("## 설치\n설치 안내").summary == release(nil).summary)
    featureCheck(release("```\n## 요약\n잘못된 요약\n```\n## 요약\n정상\n## 설치").summary == "정상")
    featureCheck(sample.isNewer(than: "1.2.0") && !sample.isNewer(than: "1.3.0") && !sample.isNewer(than: "2.0.0"))
    featureCheck(!release(nil, draft: true).isNewer(than: "1.2.0"))
    featureCheck(!release(nil, pre: true).isNewer(than: "1.2.0"))
    featureCheck(!release(nil, url: "https://github.com.evil.test/codingnoye/gksdud/releases/tag/v3.0").isNewer(than: "1.2.0"))
    let scratch = ScratchDefaults("feature-tests"), defaults = scratch.defaults
    defer { scratch.close() }
    var now = Date(timeIntervalSince1970: 100_000), requests = 0
    var completion: ((Data?, URLResponse?, Error?) -> Void)?
    let checker = UpdateChecker(defaults: defaults, installedVersion: "1.2.0", now: { now }, fetch: { request, done in
        requests += 1; completion = done
        featureCheck(request.url?.host == "api.github.com" && request.timeoutInterval == 20)
    })
    func respond(_ status: Int, _ data: Data?) {
        completion?(data, HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: status, httpVersion: nil, headerFields: nil), nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    checker.check(); checker.check(force: true); featureCheck(requests == 1, "Coalesce concurrent requests")
    respond(200, try! JSONEncoder().encode(sample)); featureCheck(checker.available != nil && !checker.checking)
    checker.check(); featureCheck(requests == 1)
    now += 86401; checker.check(); featureCheck(requests == 2)
    respond(503, nil); featureCheck(checker.available != nil && checker.error != nil, "Offline checks preserve cached notification")
    let relaunched = UpdateChecker(defaults: defaults, installedVersion: "1.2.0")
    featureCheck(relaunched.available != nil)
    let upgraded = UpdateChecker(defaults: defaults, installedVersion: "1.3.0")
    featureCheck(upgraded.available == nil)
    checker.check(force: true); respond(200, Data("{}".utf8)); featureCheck(checker.error != nil && checker.available != nil)
    checker.check(force: true); respond(200, try! JSONEncoder().encode(release(nil, tag: "v1.2.0")))
    featureCheck(checker.available == nil && checker.error == nil)
    print("PASS: numeric versions, release summary boundaries, trusted release URLs, daily schedule, retry/cache/offline/upgrade behavior")
    do { try runUpdateInstallTests() } catch { preconditionFailure("Installer tests: \(error)") }
    runPrereleaseTests()
    runOptionInputTests()
    runOptionRepeatTests()
    runNativeOptionSymbolTests()
}

// Exercises only the latch: calling a guarded system closure here would change the live setup whenever its guard is missing.
func runSystemAccessTests() {
    featureCheck(SystemAccess.isLocked, "latch must be locked in --self-test")
    let recorded = SystemAccess.denied.count
    featureCheck(!SystemAccess.permits("probe"), "a locked latch must refuse every action")
    featureCheck(SystemAccess.denied.count == recorded + 1 && SystemAccess.denied.last == "probe", "a refusal must be recorded in denied")
    do { try SystemAccess.check("probe"); featureCheck(false, "check must throw while locked") }
    catch { featureCheck((error as? SystemAccess.Denied)?.action == "probe" && error.localizedDescription.contains("probe"), "check must throw SystemAccess.Denied naming the action") }
    featureCheck(SystemAccess.denied.suffix(2) == ["probe", "probe"], "check must record its refusal too")
    print("PASS: system access latch locked in --self-test, refusals recorded, check throws SystemAccess.Denied")
}

// A malformed or conflicting launch must stop at usage, locked, instead of starting the normal app, the live probe or the integration
// test beside the user's own gksdud. The argument lists of build.sh, CI, CONTRIBUTING, the capture script and the updater must still work.
func runLaunchModeTests() {
    func parsed(_ arguments: [String]) -> String { let mode = LaunchMode(arguments: arguments); return "\(arguments) gives \(mode)\(mode.locksSystemAccess ? "" : ", unlocked")" }
    let rejected = [
        ["--render-keyboard-ui"], ["--render-keyboard-ui", ""], ["--render-keyboard-ui", "--self-test"], ["--localization-test"], ["--localization-test", "ja", "extra"],
        ["--self-test", "--probe-option-input"], ["--localization-test", "ja", "--probe-option-input"], ["--capture-screenshots", "/private/tmp/shots", "--probe-option-input"],
        ["--localization-test", "--probe-option-input", "--strict", "-AppleLanguages", "(--probe-option-input)"], ["--self-test", "-AppleLanguages", "--probe-option-input"],
        ["--integration-test", "--render-keyboard-ui"], ["--self-test", "--self-test"], ["--self-test", "--install-update"], ["--self-tset"], ["self-test"], ["--"],
        ["--strict"], ["--self-test", "--settings"], ["--settings", "--settings"], ["--localization-test", "ja", "--strict", "--strict"], ["--self-test", "--appearance", "dark"],
        ["--capture-screenshots"], ["--capture-screenshots", "--appearance", "dark"], ["--capture-screenshots", "/private/tmp/shots", "--appearance"],
        ["--capture-screenshots", "/x", "--appearance", "sepia"], ["--capture-screenshots", "/x", "--appearance", "dark", "--appearance", "light"],
    ]
    let started = rejected.filter { arguments in
        let mode = LaunchMode(arguments: arguments)
        if case .usage = mode, mode.locksSystemAccess { return false }
        return true
    }
    featureCheck(started.isEmpty, "malformed or conflicting arguments must give usage, locked: \(started.map(parsed).joined(separator: "; "))")
    let shots = "/private/tmp/shots", ui = "/private/tmp/gksdud-ui", update = "/private/tmp/gksdud-update-1"
    let locked: [([String], LaunchMode)] = [
        (["--self-test", "-AppleLanguages", "(ko)"], .selfTest), (["--self-test"], .selfTest),
        (["--localization-test", "ko", "-AppleLanguages", "(en-US)"], .localizationTest(language: "ko", strict: false)),
        (["--localization-test", "ko", "--strict", "-AppleLanguages", "(en-US)"], .localizationTest(language: "ko", strict: true)),
        (["--localization-test", "zh-Hant", "-AppleLanguages", "(zh-Hant)"], .localizationTest(language: "zh-Hant", strict: false)),
        (["--localization-test", "ja", "--strict", "-AppleLanguages", "(ja)"], .localizationTest(language: "ja", strict: true)),
        (["--capture-screenshots", "/repo/docs/images/ja", "--appearance", "light", "-AppleLanguages", "(ja)"], .captureScreenshots(directory: "/repo/docs/images/ja", dark: false)),
        (["--capture-screenshots", "/private/tmp/gksdud-captures/ja-dark", "--appearance", "dark", "-AppleLanguages", "(ja)"], .captureScreenshots(directory: "/private/tmp/gksdud-captures/ja-dark", dark: true)),
        (["--render-keyboard-ui", ui], .renderKeyboardUI(directory: ui)), (["--render-keyboard-ui", ui, "-AppleLanguages", "(ko)"], .renderKeyboardUI(directory: ui)),
        (["--capture-screenshots", shots, "-AppleLanguages", "(ja)"], .captureScreenshots(directory: shots, dark: false)),
        (["--capture-screenshots", shots, "--appearance", "dark"], .captureScreenshots(directory: shots, dark: true)),
        (["-AppleLanguages", "(ja)", "--capture-screenshots", shots, "--appearance", "light"], .captureScreenshots(directory: shots, dark: false)),
    ]
    let unlocked: [([String], LaunchMode)] = [
        ([], .app(showSettings: false)), (["--settings"], .app(showSettings: true)), (["-psn_0_12345"], .app(showSettings: false)), (["-psn_0_12345", "--settings"], .app(showSettings: true)),
        (["--install-update", update, update + "/expanded/gksdud.app", "1.4.0", "4242"], .installUpdate), (["--probe-option-input"], .probeOptionInput), (["--integration-test"], .integrationTest),
    ]
    let misread = locked.filter { LaunchMode(arguments: $0.0) != $0.1 || !$0.1.locksSystemAccess } + unlocked.filter { LaunchMode(arguments: $0.0) != $0.1 || $0.1.locksSystemAccess }
    featureCheck(misread.isEmpty, "launch arguments misread: \(misread.map { "\(parsed($0.0)), expected \($0.1)" }.joined(separator: "; "))")
    func reason(_ arguments: [String]) -> String { if case .usage(let reason) = LaunchMode(arguments: arguments) { return reason }; return "" }
    let named = [(["--self-tset"], "--self-tset"), (["self-test"], "self-test"), (["--render-keyboard-ui"], "--render-keyboard-ui"), (["--self-test", "--probe-option-input"], "--probe-option-input"),
                 (["--strict"], "--localization-test"), (["--capture-screenshots", shots, "--appearance", "sepia"], "sepia")]
    featureCheck(named.allSatisfy { reason($0.0).contains($0.1) }, "usage must name what is wrong: \(named.map { reason($0.0) })")
    print("PASS: launch modes: the arguments of build.sh, CI, CONTRIBUTING and the capture script lock; the app, updater, probe and integration test do not; missing or dash values, unknown, bare, repeated, conflicting and misplaced arguments give usage")
    // scripts/capture-screenshots.sh reads the marker without running the app. The bare binary that CI's crash diagnosis runs has no Info.plist.
    guard Bundle.main.bundleURL.pathExtension == "app" else { print("SKIP: GKSDUDLaunchModes marker (bare binary without Info.plist)"); return }
    let marker = Bundle.main.object(forInfoDictionaryKey: "GKSDUDLaunchModes")
    featureCheck(marker as? Int == LaunchMode.contract, "Info.plist's GKSDUDLaunchModes is \(marker.map { "\($0)" } ?? "missing"), expected LaunchMode.contract \(LaunchMode.contract)")
    print("PASS: Info.plist's GKSDUDLaunchModes \(LaunchMode.contract) matches LaunchMode.contract")
}

func runOptionInputTests() {
    let korean = InputSourceIdentity(id: "ko", language: "ko"), english = InputSourceIdentity(id: "en", language: "en")
    var current = korean, front: pid_t? = 42, clock = 0.0
    var events: [CGEvent] = [], transitions: [String] = [], jobs: [(Double, () -> Void)] = []
    var selectWorks = true, selectedChanges = true, englishAvailable = true, canReturn = true
    var warnings: [String] = []
    let marker: Int64 = 191919
    let controller = OptionInputController(environment: .init(current: { current }, english: { englishAvailable ? english : nil }, select: {
        transitions.append($0.id)
        if $0 == korean && !canReturn { return false }
        if selectWorks && selectedChanges { current = $0 }
        return selectWorks
    }, frontmost: { front }, post: { events.append($0) }, later: { delay, action in jobs.append((clock + delay, action)) }, clock: { clock }, deadState: { _, event, state in
        if state != 0 { return 0 }
        return [14, 32, 34, 45, 50].contains(event.getIntegerValueField(.keyboardEventKeycode))
            && event.flags.contains(.maskAlternate) && !event.flags.contains(.maskShift) ? 1 : 0
    }), marker: marker)
    controller.report = { warnings.append($0) }
    func event(_ key: Int64, _ flags: CGEventFlags = [], _ down: Bool = true) -> CGEvent {
        let value = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down)!
        value.flags = flags; return value
    }
    func drain() {
        var count = 0
        while !jobs.isEmpty {
            jobs.sort { $0.0 < $1.0 }; let job = jobs.removeFirst(); clock = job.0; job.1()
            count += 1; featureCheck(count < 1000, "Transactions must terminate")
        }
    }
    let option: CGEventFlags = [.maskAlternate], both: CGEventFlags = [.maskAlternate, .maskShift]
    for flags in [option, both] {
        for key: Int64 in [0, 19, 25, 28, 42, 49] {
            featureCheck(OptionKeyPolicy.matches(code: key, flags: flags))
        }
    }
    for key: Int64 in [36, 48, 51, 53, 57, 80, 102, 104, 123, 124, 125, 126] { featureCheck(!OptionKeyPolicy.matches(code: key, flags: both)) }
    for extra: CGEventFlags in [.maskCommand, .maskControl, .maskSecondaryFn] { featureCheck(!OptionKeyPolicy.matches(code: 25, flags: both.union(extra))) }
    featureCheck(!controller.handle(event(25, both), mode: .none, active: true))
    featureCheck(!controller.handle(event(25, both), mode: .english, active: false))
    current = english; featureCheck(!controller.handle(event(25, both), mode: .english, active: true))
    // Japanese never starts a round trip, and Konkani's kok tag is not Korean.
    for other in [InputSourceIdentity(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", language: "ja"), InputSourceIdentity(id: "com.apple.keylayout.Konkani", language: "kok")] {
        current = other
        featureCheck(!controller.handle(event(25, both), mode: .english, active: true) && !controller.busy && jobs.isEmpty && transitions.isEmpty && events.isEmpty,
            "\(other.id) (\(other.language)) must not start an English round trip")
    }
    print("PASS: option characters stay Korean-only (Konkani, Japanese)")
    let letterKeys: [Int64] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 45, 46]
    for source in [korean, english] {
        current = source
        for flags in [option, both, both.union(.maskAlphaShift)] {
            for down in [true, false] {
                for key in OptionKeyPolicy.printable {
                    let stroke = event(key, flags, down)
                    let expected = letterKeys.contains(key) ? flags.subtracting(.maskAlternate) : flags
                    featureCheck(!controller.handle(stroke, mode: .block, active: true) && stroke.flags == expected,
                        "Block only letter keys, preserving numbers, punctuation, space and keypad: \(key)")
                }
            }
        }
    }
    for extra: CGEventFlags in [.maskCommand, .maskControl, .maskSecondaryFn] {
        let shortcut = event(0, both.union(extra))
        featureCheck(!controller.handle(shortcut, mode: .block, active: true) && shortcut.flags == both.union(extra), "Block mode keeps shortcuts")
    }
    current = korean
    let keypadKeys: [Int64] = [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95]
    for key in keypadKeys {
        for flags in [option, both, option.union(.maskNumericPad), both.union([.maskNumericPad, .maskAlphaShift])] {
            featureCheck(!OptionKeyPolicy.matches(code: key, flags: flags), "Keypad must not start an English round trip")
            for repeated in [false, true] {
                let stroke = event(key, flags)
                stroke.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
                featureCheck(!controller.handle(stroke, mode: .english, active: true) && stroke.flags == flags,
                    "Keypad down/repeat must pass unchanged: \(key)")
            }
            let release = event(key, flags.subtracting(.maskAlternate), false)
            featureCheck(!controller.handle(release, mode: .english, active: true)
                && release.flags == flags.subtracting(.maskAlternate), "Keypad must retain its physical key-up")
        }
    }
    featureCheck(jobs.isEmpty && events.isEmpty && transitions.isEmpty && warnings.isEmpty,
        "Idle keypad input must not schedule, replay, switch or warn")
    for flags in [option, both] {
        for repeatKey in [false, true] {
            let grave = event(50, flags)
            grave.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            featureCheck(!controller.handle(grave, mode: .english, active: true) && grave.flags == flags,
                "Korean Option-won must reach the native IME immediately, including repeats")
        }
        featureCheck(!controller.handle(event(50, [], false), mode: .english, active: true), "Native symbol keeps its physical key-up")
    }
    englishAvailable = false
    featureCheck(!controller.handle(event(50, option), mode: .english, active: true), "Native backtick needs no English source")
    featureCheck(!controller.handle(event(83, option), mode: .english, active: true), "Native keypad needs no English source")
    englishAvailable = true
    featureCheck(!controller.handle(event(0), mode: .english, active: true), "Native backtick must not leave an English dead key pending")
    featureCheck(!controller.busy && jobs.isEmpty && events.isEmpty && transitions.isEmpty && warnings.isEmpty,
        "Native symbols must not switch sources, queue input or warn")
    featureCheck(controller.handle(event(25, both), mode: .english, active: true))
    featureCheck(controller.handle(event(25, [], false), mode: .english, active: true))
    featureCheck(controller.handle(event(0), mode: .english, active: true))
    drain()
    featureCheck(current == korean && !controller.busy && transitions == ["en", "ko"])
    featureCheck(events.count == 3 && events[0].type == .keyDown && events[1].type == .keyUp)
    featureCheck(events[0].flags == both && events[2].getIntegerValueField(.keyboardEventKeycode) == 0)
    featureCheck(events[0].getIntegerValueField(.eventSourceUserData) == marker)
    featureCheck(!controller.handle(events[0], mode: .english, active: true), "No synthetic recursion")
    events.removeAll(); transitions.removeAll()
    for key: Int64 in [28, 19, 25] {
        featureCheck(controller.handle(event(key, option), mode: .english, active: true))
        featureCheck(controller.handle(event(key, option, false), mode: .english, active: true))
    }
    featureCheck(controller.handle(event(0), mode: .english, active: true))
    featureCheck(controller.handle(event(27, option), mode: .english, active: true))
    drain()
    featureCheck(transitions == ["en", "ko"], "Rapid Option strokes share one round trip")
    // An Option stroke behind waiting text is released with it, in order, for its own transaction.
    featureCheck(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [28, 28, 19, 19, 25, 25, 0, 27])
    events.removeAll(); transitions.removeAll()
    for (accent, base): (Int64, Int64) in [(14, 0), (32, 32), (34, 0), (45, 45), (14, 83)] {
        let baseFlags: [CGEventFlags] = base == 83 ? [[], .maskShift, option, both] : [[], .maskShift]
        for flags in baseFlags {
            featureCheck(controller.handle(event(accent, option), mode: .english, active: true))
            featureCheck(!controller.busy && transitions.isEmpty, "Dead keys wait for a composing stroke")
            featureCheck(controller.handle(event(accent, [], false), mode: .english, active: true))
            featureCheck(controller.handle(event(base, flags), mode: .english, active: true))
            featureCheck(controller.handle(event(base, flags, false), mode: .english, active: true))
            featureCheck(controller.handle(event(1), mode: .english, active: true))
            featureCheck(controller.handle(event(1, [], false), mode: .english, active: true))
            drain()
            featureCheck(current == korean && !controller.busy && transitions == ["en", "ko"])
            featureCheck(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [accent, accent, base, base, 1, 1],
                "Accent composition must precede the next Hangul stroke, including keypad continuation")
            featureCheck(events[2].flags == flags && events[3].flags == flags, "Composing letter preserves Shift")
            featureCheck(!controller.handle(event(base), mode: .english, active: true)
                && !controller.handle(event(base, [], false), mode: .english, active: true), "Accent must release the next plain key")
            events.removeAll(); transitions.removeAll()
        }
    }
    englishAvailable = false
    featureCheck(!controller.handle(event(25, both), mode: .english, active: true)); englishAvailable = true
    selectWorks = false
    _ = controller.handle(event(25, both), mode: .english, active: true); drain()
    featureCheck(!controller.busy && events.count == 2 && current == korean, "Failed switch replays original once")
    _ = controller.handle(event(25, [], false), mode: .english, active: true)
    selectWorks = true; selectedChanges = false; events.removeAll()
    _ = controller.handle(event(25, both), mode: .english, active: true); drain()
    featureCheck(!controller.busy && events.count == 2, "Missing source confirmation times out")
    _ = controller.handle(event(25, [], false), mode: .english, active: true)
    selectedChanges = true; events.removeAll(); canReturn = false
    _ = controller.handle(event(25, both), mode: .english, active: true)
    _ = controller.handle(event(0), mode: .english, active: true)
    drain()
    featureCheck(!controller.busy && current == english && events.count == 2, "Failed return must not inject queued Hangul in English")
    _ = controller.handle(event(25, [], false), mode: .english, active: true)
    canReturn = true; current = korean; events.removeAll()
    _ = controller.handle(event(25, both), mode: .english, active: true)
    _ = controller.handle(event(0), mode: .english, active: true)
    front = 99; controller.cancel(focusChanged: true); drain()
    featureCheck(events.isEmpty && !controller.busy, "Never replay queued text into a different app")
    featureCheck(!warnings.isEmpty)
    featureCheck(InputSources.source(id: "io.gksdud.nonexistent-input-source") == nil, "Unavailable input sources must not crash")
    if let abc = InputSources.source(id: "com.apple.keylayout.ABC"), let identity = InputSources.read(abc)?.identity {
        let layoutRead = ScratchDefaults("layout-read-test")
        defer { layoutRead.close() }
        let owner = AppDelegate(engine: Engine(defaults: layoutRead.defaults, discover: { [] }))
        let translate = owner.makeOptionInput().environment.deadState
        for (accent, base): (Int64, Int64) in [(14, 0), (32, 32), (34, 0), (45, 45), (14, 83)] {
            let pending = translate(identity, event(accent, option), 0) ?? 0
            featureCheck(pending != 0, "ABC accent must enter composition: \(accent)")
            for flags: CGEventFlags in [[], .maskShift] {
                featureCheck(translate(identity, event(base, flags), pending) == 0,
                    "A composed accent must release the following Hangul stroke")
            }
            featureCheck(translate(identity, event(accent, both), 0) == 0, "Option-Shift accent is a standalone mark")
        }
        featureCheck((translate(identity, event(50, option), 0) ?? 0) != 0, "ABC Option-grave is a dead key, unlike Korean Option-won")
    } else {
        print("SKIP: native ABC accent check (ABC input source is unavailable); simulated dead-key checks passed")
    }
    print("PASS: Option/Option-Shift printable keys, shortcut exclusions, block mode, ordered round trip, dead keys, source failures, focus cancellation, synthetic bypass")
}

// Opt-in native input probe: directs generated test keys only to its own window.
// It does not install a global event tap, touch HID mappings, or replace an app.
func probeOptionInput() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular); app.finishLaunching()
    guard AXIsProcessTrusted() else { throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Native input probe requires accessibility permission."]) }
    let previousApp = NSWorkspace.shared.frontmostApplication
    let savedSource = TISCopyCurrentKeyboardInputSource()!.takeRetainedValue()
    let scratch = ScratchDefaults("input-probe")
    let delegate = AppDelegate(engine: Engine(defaults: scratch.defaults, discover: { [] }))
    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = "gksdud 특수문자 입력 실험"
    let text = NSTextView(frame: NSRect(x: 20, y: 20, width: 480, height: 110))
    text.font = .systemFont(ofSize: 24); panel.contentView!.addSubview(text)
    panel.center(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(text); app.activate(ignoringOtherApps: true)
    func pump(_ duration: TimeInterval) {
        let end = Date(timeIntervalSinceNow: duration)
        while Date() < end {
            if let event = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.005), inMode: .default, dequeue: true) { app.sendEvent(event) }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
        }
    }
    pump(0.5)
    guard panel.isKeyWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
        panel.orderOut(nil); scratch.close()
        throw NSError(domain: "probe", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unlock the Mac and activate the test window before running the native input probe."])
    }
    var environment = delegate.makeOptionInput().environment
    environment.post = { $0.postToPid(getpid()) }
    var selections = 0
    let select = environment.select
    environment.select = { source in selections += 1; return select(source) }
    let controller = OptionInputController(environment: environment, marker: delegate.nativePulseMarker)
    controller.report = { print("PROBE notice: \($0)") }
    var mode = SpecialCharacterMode.english
    let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
        guard let cg = event.cgEvent else { return event }
        return controller.handle(cg, mode: mode, active: true) ? nil : NSEvent(cgEvent: cg)
    }
    defer {
        controller.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        _ = TISSelectInputSource(savedSource)
        panel.orderOut(nil); previousApp?.activate(options: [])
        scratch.close()
    }
    func enabledSource(_ language: InputLanguage) -> TISInputSource? {
        delegate.environment.inputSources.enabled().first { InputLanguage.match($0.language) == language }.flatMap { InputSources.source(id: $0.id) }
    }
    guard let korean = enabledSource(.korean) else { throw NSError(domain: "probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Korean input source is unavailable."]) }
    func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            if OptionKeyPolicy.keypad.contains(Int64(code)) { event.flags.insert(.maskNumericPad) }
            event.postToPid(getpid())
        }
    }
    var passed = 0
    let keypadCases: [(CGKeyCode, String)] = [(65, "."), (67, "*"), (69, "+"), (75, "/"), (78, "-"), (81, "="),
        (82, "0"), (83, "1"), (84, "2"), (85, "3"), (86, "4"), (87, "5"), (88, "6"), (89, "7"), (91, "8"), (92, "9")]
    var cases: [(CGKeyCode, CGEventFlags, String)] = [(25, [.maskAlternate, .maskShift], "·"), (28, [.maskAlternate], "•"), (19, [.maskAlternate], "™"), (27, [.maskAlternate], "–"), (27, [.maskAlternate, .maskShift], "—"), (8, [.maskAlternate], "ç"), (50, [.maskAlternate], "`"), (50, [.maskAlternate, .maskShift], "~")]
    for (code, symbol) in keypadCases {
        cases.append((code, [.maskAlternate], symbol))
        cases.append((code, [.maskAlternate, .maskShift], symbol))
    }
    for (code, flags, symbol) in cases {
        text.inputContext?.discardMarkedText(); text.string = ""
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(text); app.activate(ignoringOtherApps: true); pump(0.1)
        let selectionResult = TISSelectInputSource(korean); pump(0.2)
        guard selectionResult == noErr, environment.current()?.language.hasPrefix("ko") == true,
              panel.isKeyWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            throw NSError(domain: "probe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not prepare an active Korean input context."])
        }
        key(15); pump(0.03); key(40); pump(0.03)
        let before = selections
        key(code, flags)
        // Deliberately queue the next Hangul syllable before the 60 ms return.
        pump(0.01); key(1); key(40); pump(0.5)
        let expected = "가\(symbol)나"
        let ok = text.string == expected && environment.current()?.language.hasPrefix("ko") == true
            && (!keypadCases.contains(where: { $0.0 == code }) || selections == before)
        if ok { passed += 1 }
        print("PROBE \(ok ? "PASS" : "FAIL"): expected=\(expected), actual=\(text.string), returned=\(environment.current()?.language ?? "nil")")
    }
    let accentCases: [(CGKeyCode, CGKeyCode, CGEventFlags, String)] = [
        (14, 0, [], "가á나"), (32, 32, [], "가ü나"), (34, 0, [], "가â나"), (45, 45, [], "가ñ나"),
        (14, 0, .maskShift, "가Á나"), (32, 32, .maskShift, "가Ü나"), (34, 0, .maskShift, "가Â나"), (45, 45, .maskShift, "가Ñ나"),
        (14, 83, [], "가´1나"), (14, 83, .maskAlternate, "가´1나")]
    for (accentKey, baseKey, flags, expected) in accentCases {
        text.inputContext?.discardMarkedText(); text.string = ""
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(text); app.activate(ignoringOtherApps: true); pump(0.1)
        let selectionResult = TISSelectInputSource(korean); pump(0.2)
        guard selectionResult == noErr, environment.current()?.language.hasPrefix("ko") == true,
              panel.isKeyWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            throw NSError(domain: "probe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not prepare an active Korean input context."])
        }
        key(15); pump(0.03); key(40); pump(0.03)
        key(accentKey, [.maskAlternate]); pump(0.03); key(baseKey, flags)
        pump(0.01); key(1); key(40); pump(0.5)
        let ok = text.string == expected && environment.current()?.language.hasPrefix("ko") == true
        if ok { passed += 1 }
        print("PROBE \(ok ? "PASS" : "FAIL"): expected=\(expected), actual=\(text.string), returned=\(environment.current()?.language ?? "nil")")
    }
    for rapidMode in [SpecialCharacterMode.english, .block] {
        controller.cancel(); mode = rapidMode
        text.inputContext?.discardMarkedText(); text.string = ""
        let selected = TISSelectInputSource(korean); pump(0.2)
        guard selected == noErr, environment.current()?.language.hasPrefix("ko") == true,
              panel.isKeyWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            throw NSError(domain: "probe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not prepare the rapid-symbol input context."])
        }
        key(15); key(40); pump(0.03)
        for _ in 0..<10 { key(50, [.maskAlternate]) }
        key(1); key(40); pump(0.3)
        let expected = "가" + String(repeating: "`", count: 10) + "나"
        let ok = text.string == expected && !controller.busy && environment.current()?.language.hasPrefix("ko") == true
        if ok { passed += 1 }
        print("PROBE \(ok ? "PASS" : "FAIL"): rapid backticks mode=\(mode), expected=\(expected), actual=\(text.string)")
    }
    guard let english = enabledSource(.english) else { throw NSError(domain: "probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "English input source is unavailable."]) }
    let blockCases: [(CGKeyCode, CGEventFlags, Bool)] = [(0, [.maskAlternate], true), (0, [.maskAlternate, .maskShift], true),
        (14, [.maskAlternate], true), (19, [.maskAlternate], false), (50, [.maskAlternate], false), (42, [.maskAlternate], false)]
    for source in [korean, english] {
        for (code, flags, letter) in blockCases {
            var expected = ""
            for reference in [true, false] {
                controller.cancel(); mode = reference ? .none : .block
                text.inputContext?.discardMarkedText(); text.string = ""
                let selected = TISSelectInputSource(source); pump(0.2)
                guard selected == noErr, environment.current() == InputSources.read(source)?.identity,
                      panel.isKeyWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
                    throw NSError(domain: "probe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not prepare the block-mode input context."])
                }
                key(code, reference && letter ? flags.subtracting(.maskAlternate) : flags)
                pump(0.03); key(49); pump(0.1)
                if reference { expected = text.string; continue }
                let ok = !expected.isEmpty && text.string == expected && environment.current() == InputSources.read(source)?.identity
                if ok { passed += 1 }
                print("PROBE \(ok ? "PASS" : "FAIL"): block key=\(code), source=\(environment.current()?.language ?? "nil"), expected=\(expected), actual=\(text.string)")
            }
        }
    }
    let total = cases.count + accentCases.count + 2 + blockCases.count * 2
    print("PROBE RESULT: \(passed)/\(total) native AppKit cases")
    guard passed == total else { throw NSError(domain: "probe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native input expectations failed."]) }
}

func runUpdateInstallTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gksdud-installer-test-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    ScratchDefaults.removeAtExit(root)
    defer { try? fm.removeItem(at: root) }
    let installed = root.appendingPathComponent("Installed.app"), candidate = root.appendingPathComponent("Candidate.app")
    func writeBundle(_ url: URL, _ value: String) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try value.write(to: url.appendingPathComponent("version"), atomically: true, encoding: .utf8)
    }
    func version(_ url: URL) -> String { try! String(contentsOf: url.appendingPathComponent("version"), encoding: .utf8) }
    func rejected(_ action: () throws -> Void) { do { try action(); preconditionFailure("Expected rejection") } catch {} }
    try writeBundle(installed, "old"); try writeBundle(candidate, "new")
    rejected { try AppReplacement.replace(installed: installed, candidate: candidate, validate: { _, _ in throw UpdateFailure("invalid signature") }, launch: { _ in preconditionFailure() }) }
    featureCheck(version(installed) == "old", "Validate before moving the installed app")
    rejected { try AppReplacement.replace(installed: installed, candidate: candidate, validate: { _, _ in }, launch: { _ in }, move: { from, to in
        if from.lastPathComponent.hasPrefix(".gksdud-update-") { throw UpdateFailure("move failed") }
        try fm.moveItem(at: from, to: to)
    }) }
    featureCheck(version(installed) == "old", "Failed replacement restores the old path")
    var launches: [String] = []
    rejected { try AppReplacement.replace(installed: installed, candidate: candidate, validate: { _, _ in }, launch: { url in
        launches.append(version(url)); if version(url) == "new" { throw UpdateFailure("launch failed") }
    }) }
    featureCheck(version(installed) == "old" && launches == ["new", "old"], "Failed launch rolls back and restarts the old bundle")
    try AppReplacement.replace(installed: installed, candidate: candidate, validate: { new, old in featureCheck(version(new) == "new" && version(old) == "old") }, launch: { featureCheck(version($0) == "new") })
    featureCheck(version(installed) == "new" && version(candidate) == "new")
    let remaining = try fm.contentsOfDirectory(atPath: root.path)
    featureCheck(remaining.allSatisfy { !$0.hasPrefix(".gksdud-") })
    let archive = root.appendingPathComponent("test.zip")
    try Data("abc".utf8).write(to: archive)
    let valid = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  test.zip\n"
    try UpdateValidation.checksum(archive, text: valid, name: "test.zip")
    rejected { try UpdateValidation.checksum(archive, text: valid + valid, name: "test.zip") }
    rejected { try UpdateValidation.checksum(archive, text: valid, name: "other.zip") }
    try Data("tampered".utf8).write(to: archive)
    rejected { try UpdateValidation.checksum(archive, text: valid, name: "test.zip") }
    let names = "gksdud.app/\ngksdud.app/Contents/MacOS/gksdud\n"
    let listing = "drwxr-xr-x  2.1 unx 0 bx stor 00-Sep-00 00:00 gksdud.app/\n-rwxr-xr-x  2.1 unx 42 bx defN 00-Sep-00 00:00 gksdud.app/Contents/MacOS/gksdud\n"
    try UpdateValidation.archiveNames(names, listing: listing)
    rejected { try UpdateValidation.archiveNames("gksdud.app/../../escape", listing: listing) }
    rejected { try UpdateValidation.archiveNames("/gksdud.app/file", listing: listing) }
    rejected { try UpdateValidation.archiveNames(names, listing: listing.replacingOccurrences(of: "-rwx", with: "lrwx")) }
    rejected { try UpdateValidation.archiveNames(names, listing: listing.replacingOccurrences(of: "42 bx", with: "999999999 bx")) }
    var release = AppRelease(tag_name: "v1.3.0", html_url: "https://github.com/codingnoye/gksdud/releases/tag/v1.3.0", body: nil, draft: false, prerelease: false)
    release.assets = [ReleaseAsset(name: "test.zip", browser_download_url: "https://github.com/codingnoye/gksdud/releases/download/v1.3.0/test.zip", size: 100)]
    let assetURL = try release.assetURL(named: "test.zip", limit: 100)
    featureCheck(assetURL.host == "github.com")
    rejected { _ = try release.assetURL(named: "test.zip", limit: 99) }
    release.assets = [ReleaseAsset(name: "test.zip", browser_download_url: "https://evil.test/test.zip", size: 100)]
    rejected { _ = try release.assetURL(named: "test.zip", limit: 100) }
    rejected { _ = try UpdateValidation.installedRequirement(candidate) }
    // Real children: timeout must reap the process before replacement can roll back.
    for arguments in [["5"], ["-c", "trap '' TERM; exec /bin/sleep 5"]] {
        var pid: pid_t = 0
        rejected {
            try UpdateProcessLauncher.launch(executable: URL(fileURLWithPath: arguments.count == 1 ? "/bin/sleep" : "/bin/sh"), arguments: arguments, timeout: 0.1, settle: 0) {
                pid = $0.processIdentifier; return false
            }
        }
        featureCheck(pid > 1 && kill(pid, 0) == -1 && errno == ESRCH, "Timeout must leave no live child, including one ignoring SIGTERM")
    }
    rejected { try UpdateProcessLauncher.launch(executable: URL(fileURLWithPath: "/usr/bin/false"), timeout: 0.1, settle: 0.05, ready: { _ in true }) }
    let child = try UpdateProcessLauncher.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.2, settle: 0.05, ready: { _ in true })
    featureCheck(child.isRunning)
    try UpdateProcessLauncher.stop(child)
    var rollbackSawDeadChild = false, failedPID: pid_t = 0
    rejected {
        try AppReplacement.replace(installed: installed, candidate: candidate, validate: { _, _ in }, launch: { _ in
            if failedPID == 0 {
                try UpdateProcessLauncher.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.05, settle: 0) { failedPID = $0.processIdentifier; return false }
            } else { rollbackSawDeadChild = kill(failedPID, 0) == -1 && errno == ESRCH }
        })
    }
    featureCheck(rollbackSawDeadChild, "Old app relaunch waits for timed-out child termination")
    print("PASS: launch readiness, early exit, timeout termination, SIGKILL fallback, child exit before rollback")
    print("PASS: archive checksums/paths/link and size rejection, release asset origin, validation before replacement, move/launch rollback, successful replacement")
}

func runPrereleaseTests() {
    let scratch = ScratchDefaults("channel-tests"), defaults = scratch.defaults
    defer { scratch.close() }
    let tag = "pre-v1.3.0"
    let preview = AppRelease(tag_name: tag, html_url: "https://github.com/codingnoye/gksdud/releases/tag/\(tag)", body: nil, draft: false, prerelease: true)
    featureCheck(!preview.isNewer(than: "1.2.0"))
    var completion: ((Data?, URLResponse?, Error?) -> Void)?
    let checker = UpdateChecker(defaults: defaults, installedVersion: "1.2.0", fetch: { request, done in
        featureCheck(request.url?.path == "/repos/codingnoye/gksdud/releases/latest" && request.url?.query == nil)
        completion = done
    })
    checker.check()
    completion?(try! JSONEncoder().encode(preview), HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    featureCheck(checker.available == nil && checker.error != nil, "Prerelease responses are rejected")
    print("PASS: stable-only endpoint and prerelease rejection")
}

func runOptionRepeatTests() {
    let ko = InputSourceIdentity(id: "ko", language: "ko"), en = InputSourceIdentity(id: "en", language: "en")
    var current = ko, clock = 0.0, posts: [CGEvent] = [], jobs: [(Double, () -> Void)] = []
    let controller = OptionInputController(environment: .init(current: { current }, english: { en }, select: { current = $0; return true },
        frontmost: { 42 }, post: { posts.append($0) }, later: { jobs.append((clock + $0, $1)) }, clock: { clock }, deadState: { _, _, _ in 0 }), marker: 998877)
    func event(_ code: CGKeyCode = 25, down: Bool = true, repeatKey: Bool = false, option: Bool = true) -> CGEvent {
        let value = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        value.flags = option ? [.maskAlternate] : []
        value.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return value
    }
    func handle(_ event: CGEvent) -> Bool { controller.handle(event, mode: .english, active: true) }
    func drain() {
        var turns = 0
        while !jobs.isEmpty || !posts.isEmpty {
            while !posts.isEmpty { _ = handle(posts.removeFirst()) }
            if !jobs.isEmpty { jobs.sort { $0.0 < $1.0 }; let job = jobs.removeFirst(); clock = job.0; job.1() }
            turns += 1; featureCheck(turns < 1000)
        }
    }
    _ = handle(event()); drain()
    _ = handle(event(repeatKey: true))
    _ = handle(event(0, option: false)) // ordinary text prevents merging subsequent repeats
    _ = handle(event(0, down: false, option: false))
    _ = handle(event(repeatKey: true))
    _ = handle(event(down: false))
    drain()
    featureCheck(!handle(event(option: false)))
    featureCheck(!handle(event(down: false, option: false)), "Replayed repeat must not reclaim the already-consumed physical key-up")
    // A fresh queued stroke must still consume its own release during replay.
    _ = handle(event())
    _ = handle(event(down: false))
    _ = handle(event(0, option: false))
    _ = handle(event()); _ = handle(event(down: false)); drain()
    featureCheck(!handle(event(option: false)) && !handle(event(down: false, option: false)))
    print("PASS: repeat replay after physical release, subsequent plain key-up, queued fresh stroke balance")
}

func runNativeOptionSymbolTests() {
    let ko = InputSourceIdentity(id: "ko", language: "ko"), en = InputSourceIdentity(id: "en", language: "en")
    let nativeKeys: [CGKeyCode] = [50, 65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95]
    for (nativeKey, delivering) in nativeKeys.flatMap({ code in [false, true].map { (code, $0) } }) {
        var current = ko, clock = 0.0, jobs: [(Double, () -> Void)] = []
        var posted: [CGEvent] = [], delivered: [(Int64, CGEventType, String)] = [], transitions: [String] = []
        let controller = OptionInputController(environment: .init(current: { current }, english: { en }, select: {
            transitions.append($0.id); current = $0; return true
        }, frontmost: { 42 }, post: { posted.append($0) }, later: { jobs.append((clock + $0, $1)) }, clock: { clock },
        deadState: { _, event, _ in event.getIntegerValueField(.keyboardEventKeycode) == 50 ? 1 : 0 }), marker: 991199)
        func send(_ event: CGEvent) {
            if !controller.handle(event, mode: .english, active: true) {
                delivered.append((event.getIntegerValueField(.keyboardEventKeycode), event.type, current.id))
            }
        }
        func key(_ code: CGKeyCode, _ down: Bool = true, _ option: Bool = true, repeated: Bool = false) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = option ? [.maskAlternate] : []
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
            send(event)
        }
        func advance() {
            jobs.sort { $0.0 < $1.0 }; let job = jobs.removeFirst(); clock = job.0; job.1()
            while !posted.isEmpty { send(posted.removeFirst()) }
        }
        key(25); key(25, false)
        if delivering { advance() }
        key(nativeKey); key(nativeKey, repeated: true); key(nativeKey, false, false)
        key(0, true, false); key(0, false, false)
        var turns = 0
        while !jobs.isEmpty { advance(); turns += 1; featureCheck(turns < 1000) }
        featureCheck(transitions == ["en", "ko"] && !controller.busy)
        featureCheck(delivered.map { $0.0 } == [25, 25, Int64(nativeKey), Int64(nativeKey), Int64(nativeKey), 0, 0], "Queued native symbols preserve input order")
        featureCheck(delivered.map { $0.1 } == [.keyDown, .keyUp, .keyDown, .keyDown, .keyUp, .keyDown, .keyUp])
        featureCheck(delivered.map { $0.2 } == ["en", "en", "ko", "ko", "ko", "ko", "ko"], "Native symbols and keypad are never merged into English strokes")
        key(nativeKey, true, false); key(nativeKey, false, false)
        featureCheck(delivered.count == 9, "Queued repeats must not steal a subsequent plain symbol key-up")
    }
    print("PASS: native Option-won/keypad during selection/delivery, repeated symbols, ordered Hangul replay and balanced key-up")
}
