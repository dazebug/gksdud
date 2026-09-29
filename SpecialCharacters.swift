import AppKit
import Carbon

// This is separate from the F-key switch path. Ordinary input is only queued during
// an explicitly enabled, bounded Option-character transaction; it is never persisted.
enum SpecialCharacterMode: Int { case none, english, block }

struct OptionKeyPolicy {
    static let printable: Set<Int64> = Set(0...50).subtracting([36, 48])
        .union([65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95])
    static let keypad: Set<Int64> = [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95]
    static let letters: Set<Int64> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17,
        31, 32, 34, 35, 37, 38, 40, 45, 46]
    static func matches(code: Int64, flags: CGEventFlags) -> Bool {
        printable.contains(code) && !keypad.contains(code) && flags.contains(.maskAlternate)
            && flags.intersection([.maskCommand, .maskControl, .maskSecondaryFn]).isEmpty
    }
    static func preservesKoreanSymbol(code: Int64, flags: CGEventFlags) -> Bool {
        code == Int64(kVK_ANSI_Grave) && matches(code: code, flags: flags)
    }
}

final class OptionInputController {
    struct Environment {
        var current: () -> InputSourceIdentity?
        var english: () -> InputSourceIdentity?
        var select: (InputSourceIdentity) -> Bool
        var frontmost: () -> pid_t?
        var post: (CGEvent) -> Void
        var later: (TimeInterval, @escaping () -> Void) -> Void
        var clock: () -> TimeInterval
        // Predict only dead-key state; actual character input is performed by the English IME.
        var deadState: (InputSourceIdentity, CGEvent, UInt32) -> UInt32?
    }
    enum Phase { case idle, selecting, delivering, restoring }
    let environment: Environment
    let marker: Int64
    var report: (String) -> Void = { _ in }
    var willBegin: () -> Void = {}
    var didFinish: () -> Void = {}
    private(set) var phase = Phase.idle
    var busy: Bool { phase != .idle }
    private var original: InputSourceIdentity?
    private var destination: InputSourceIdentity?
    private var owner: pid_t?
    private var held: Set<Int64> = []
    private var queued: [CGEvent] = []
    private var strokes: [CGEvent] = []
    private var generation = 0
    private var deadline: TimeInterval = 0
    private var posted = false
    private var deliverUntil: TimeInterval = 0
    private var pendingDead: [CGEvent] = []
    private var pendingState: UInt32 = 0
    private var pendingSource: InputSourceIdentity?
    private var pendingOwner: pid_t?
    private var pendingOriginal: InputSourceIdentity?
    private var pendingSince: TimeInterval = 0

    init(environment: Environment, marker: Int64) { self.environment = environment; self.marker = marker }

    // Returns true only when this controller owns the event.
    func handle(_ event: CGEvent, mode: SpecialCharacterMode, active: Bool) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == marker { return false }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            cancel(focusChanged: true); return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if event.type == .keyUp, held.remove(code) != nil { return true }
        if busy {
            guard owner == environment.frontmost() else { cancel(focusChanged: true); return false }
            if queued.count >= 256 { cancel(); report(String(localized: "특수문자 입력이 지연되어 중단했습니다.", comment: "Special characters tab: status when too much typing piled up during an Option character round trip, so gksdud stopped it.")); return false }
            // Consecutive Option strokes share this English round trip instead of paying for one each.
            // Waiting text keeps its order; a dead key still gets its own transaction.
            if active, mode == .english, event.type == .keyDown, phase != .restoring, let destination,
               OptionKeyPolicy.matches(code: code, flags: event.flags),
               !OptionKeyPolicy.preservesKoreanSymbol(code: code, flags: event.flags),
               !queued.contains(where: { $0.type != .flagsChanged }),
               (environment.deadState(destination, event, 0) ?? 0) == 0, let copy = event.copy() {
                claimRelease(for: event)
                if phase == .selecting { strokes.append(copy) } else { postPair(copy); deliverUntil = environment.clock() + 0.06 }
                return true
            }
            guard let copy = event.copy() else { cancel(); return false }
            queued.append(copy)
            return true
        }
        guard active, mode != .none else { clearDead(); return false }
        let option = OptionKeyPolicy.matches(code: code, flags: event.flags)
        if mode == .block {
            // Deliver the stroke as the plain character, in every input language.
            clearDead()
            if (event.type == .keyDown || event.type == .keyUp), option, OptionKeyPolicy.letters.contains(code) {
                event.flags.remove(.maskAlternate)
            }
            return false
        }
        guard event.type == .keyDown else { return false }
        guard let current = environment.current(), InputLanguage.match(current.language)?.optionCharactersViaEnglish == true else { clearDead(); return false }
        if OptionKeyPolicy.preservesKoreanSymbol(code: code, flags: event.flags) { clearDead(); return false }
        if !pendingDead.isEmpty, pendingOwner != environment.frontmost() || pendingOriginal != current
            || environment.clock() - pendingSince > 30 { clearDead() }
        let continuation = !pendingDead.isEmpty && OptionKeyPolicy.printable.contains(code)
            && event.flags.intersection([.maskCommand, .maskControl, .maskSecondaryFn]).isEmpty
        if !option && !continuation { clearDead(); return false }
        guard let english = pendingSource ?? environment.english(), let copy = event.copy(),
              let front = environment.frontmost() else {
            report(String(localized: "영어 입력 소스를 추가한 뒤 다시 시도해주세요.", comment: "Special characters tab: status when an Option character should be typed as in English but no English input source is enabled.")); clearDead(); return false
        }
        // A dead key has no character to deliver yet. Retain it until the next
        // printable stroke, then replay both in one English transaction. Switching
        // back immediately after a native dead key would discard its composition.
        let nextState = environment.deadState(english, copy, pendingState) ?? 0
        if nextState != 0, pendingDead.count < 4 {
            pendingDead.append(copy); pendingState = nextState; pendingSource = english
            pendingOwner = front; pendingOriginal = current; pendingSince = environment.clock()
            claimRelease(for: event)
            return true
        }
        strokes = pendingDead + [copy]; clearDead()
        claimRelease(for: event)
        original = current; destination = english; owner = front
        willBegin()
        posted = false; phase = .selecting; generation += 1
        deadline = environment.clock() + 0.4
        let token = generation
        environment.later(0) { [weak self] in
            guard let self, self.generation == token else { return }
            guard self.owner == self.environment.frontmost() else { self.cancel(focusChanged: true); return }
            guard self.environment.select(english) else { self.cancel(); self.report(String(localized: "영어로 전환하지 못했습니다.", comment: "Special characters tab: status when gksdud could not select the English input source to type an Option character.")); return }
            self.advance(token)
        }
        return true
    }
    private func claimRelease(for event: CGEvent) {
        // Replayed repeats may arrive after the physical release was consumed.
        // Only a new physical stroke can acquire ownership of its key-up.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            held.insert(event.getIntegerValueField(.keyboardEventKeycode))
        }
    }
    private func clearDead() {
        pendingDead.removeAll(); pendingState = 0; pendingSource = nil; pendingOwner = nil; pendingOriginal = nil
    }
    private func advance(_ token: Int) {
        guard generation == token, busy else { return }
        guard owner == environment.frontmost() else { cancel(focusChanged: true); return }
        if phase == .selecting, environment.current() == destination {
            phase = .delivering; posted = true
            for event in strokes { postPair(event) }
            // CGEvent posting has no cross-application text-insertion acknowledgement.
            // This bounded grace period is intentionally experimental, not a guarantee.
            deliverUntil = environment.clock() + 0.06
            settle(token)
            return
        }
        if phase == .restoring, environment.current() == original { finish(replayOriginal: false); return }
        guard environment.clock() < deadline else {
            cancel(); report(String(localized: "입력 소스 전환을 확인하지 못했습니다. 특수문자 모드를 끄고 다시 시도해주세요.", comment: "Special characters tab: status when the switch to English or back was not confirmed in time. It suggests turning the special character option off and trying again."))
            return
        }
        environment.later(0.005) { [weak self] in self?.advance(token) }
    }
    private func settle(_ token: Int) {
        guard generation == token else { return }
        let wait = deliverUntil - environment.clock()
        if wait > 0.001 { environment.later(wait) { [weak self] in self?.settle(token) }; return }
        restore(token)
    }
    private func restore(_ token: Int) {
        guard owner == environment.frontmost() else { cancel(focusChanged: true); return }
        guard environment.current() == destination else {
            // A manual source change wins. Do not steal the user's selection.
            finish(replayOriginal: !posted); report(String(localized: "입력 소스가 바뀌어 특수문자 전환을 중단했습니다.", comment: "Special characters tab: status when the user changed the input source during an Option character round trip, so gksdud stopped it.")); return
        }
        phase = .restoring; deadline = environment.clock() + 0.4
        guard let original, environment.select(original) else {
            finish(replayOriginal: false, discard: true); report(String(localized: "한글로 돌아오지 못해 대기 중인 입력을 취소했습니다. 입력 소스를 확인해주세요.", comment: "Special characters tab: status when gksdud could not switch back to Korean input after an Option character and dropped the waiting input. Say Korean input explicitly: this option works only there.")); return
        }
        advance(token)
    }
    private func postPair(_ event: CGEvent) {
        guard let down = event.copy(), let up = event.copy() else { return }
        down.type = .keyDown; up.type = .keyUp
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        up.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        for copy in [down, up] {
            copy.setIntegerValueField(.eventSourceUserData, value: marker)
            copy.timestamp = 0
            environment.post(copy)
        }
    }
    private func finish(replayOriginal: Bool, discard: Bool = false) {
        let buffered = queued, retry = strokes
        let sameOwner = owner == environment.frontmost()
        generation += 1; phase = .idle
        original = nil; destination = nil; owner = nil; strokes.removeAll(); queued.removeAll()
        didFinish()
        if !discard && sameOwner {
            if replayOriginal { retry.forEach(postPair) }
            // Queue events re-enter the normal tap so switch keys and subsequent
            // Option strokes retain their own behavior, in original order.
            for event in buffered { environment.post(event) }
        }
    }
    func cancel(focusChanged: Bool = false) {
        clearDead()
        guard busy else { return }
        if owner == environment.frontmost(), environment.current() == destination, let original { _ = environment.select(original) }
        let restored = environment.current() == original
        // Never flush waiting Hangul while a failed restore has left English selected.
        finish(replayOriginal: !posted && restored, discard: focusChanged || !restored)
        if focusChanged { report(String(localized: "입력 창이 바뀌어 대기 중인 특수문자 입력을 취소했습니다.", comment: "Special characters tab: status when the focused window changed during an Option character round trip, so gksdud dropped the waiting input.")) }
    }
}

extension AppDelegate {
    var specialMode: SpecialCharacterMode { SpecialCharacterMode(rawValue: engine.defaults.integer(forKey: "specialCharacterMode")) ?? .none }
    @objc func changeSpecialMode(_ sender: NSButton) {
        optionInput.cancel()
        engine.defaults.set(sender.state == .on ? sender.tag : 0, forKey: "specialCharacterMode")
        refreshSpecialMode(); ensureKeyTap()
    }
    func refreshSpecialMode() {
        for button in specialButtons { button.state = button.tag == specialMode.rawValue ? .on : .off }
        specialStatus.stringValue = ""
    }
    func makeOptionInput() -> OptionInputController {
        let inputSources = environment.inputSources
        let controller = OptionInputController(environment: .init(current: { inputSources.current()?.identity }, english: {
            if let layout = InputSources.asciiLayout(), InputLanguage.match(layout.language) == .english { return layout.identity }
            return inputSources.enabled().first { InputLanguage.match($0.language) == .english }?.identity
        }, select: { inputSources.select($0.id) }, frontmost: { NSWorkspace.shared.frontmostApplication?.processIdentifier }, post: { event in
            event.post(tap: .cghidEventTap)
        }, later: { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }, clock: { ProcessInfo.processInfo.systemUptime }, deadState: { identity, event, state in
            guard let source = InputSources.source(id: identity.id), let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
            var modifiers: UInt32 = 0
            if event.flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
            if event.flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
            if event.flags.contains(.maskAlphaShift) { modifiers |= UInt32(alphaLock) }
            var next = state, length = 0
            var chars = [UniChar](repeating: 0, count: 16)
            let result = UCKeyTranslate(layout, UInt16(event.getIntegerValueField(.keyboardEventKeycode)), UInt16(kUCKeyActionDown), modifiers >> 8,
                UInt32(event.getIntegerValueField(.keyboardEventKeyboardType)), 0, &next, chars.count, &length, &chars)
            // Some layouts retain a nonzero state even after emitting the composed
            // character. Only a zero-length result means another stroke is pending.
            return result == noErr ? (length == 0 ? next : 0) : nil
        }), marker: nativePulseMarker)
        controller.report = { [weak self] text in self?.specialStatus.stringValue = text }
        controller.willBegin = { [weak self] in self?.cancelLongPress(); self?.cancelCapsRestore(); self?.refreshSpecialMode() }
        controller.didFinish = { [weak self] in
            DispatchQueue.main.async { self?.updateInputIndicator(); self?.scheduleCapsRestore() }
        }
        return controller
    }
}
