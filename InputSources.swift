import Carbon
import Foundation

struct InputSourceIdentity: Equatable {
    let id: String
    let language: String
}

struct InputSource: Equatable {
    let identity: InputSourceIdentity
    var mode: String? = nil          // kTISPropertyInputModeID
    var name = ""                    // kTISPropertyLocalizedName, which follows the app's resolved language, not the system's
    var methodName: String? = nil    // input method name; only tells apart same-named modes
    var id: String { identity.id }
    var language: String { identity.language }
}

extension InputSource {
    init(id: String, language: String, mode: String? = nil, name: String = "", methodName: String? = nil) {
        self.init(identity: InputSourceIdentity(id: id, language: language), mode: mode, name: name, methodName: methodName)
    }
}

// The only code that reads or selects the live input sources; tests and previews inject fakes instead of `system`.
struct InputSources {
    var current: () -> InputSource?
    var enabled: () -> [InputSource]  // enabled, select-capable keyboard sources in system order
    var select: (_ id: String) -> Bool
    static let system = InputSources(current: {
        TISCopyCurrentKeyboardInputSource().flatMap { read($0.takeRetainedValue()) }
    }, enabled: {
        // includeAllInstalled must stay false: true also reports the default modes of disabled input methods
        // (Kotoeri Hiragana, Ainu) as enabled and select-capable.
        let isEnabled = kTISPropertyInputSourceIsEnabled as String
        let methods = list([isEnabled: true, kTISPropertyInputSourceType as String: kTISTypeKeyboardInputMethodModeEnabled as String]).compactMap(read)
        let keyboards = list([isEnabled: true, kTISPropertyInputSourceIsSelectCapable as String: true, kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String])
        return keyboards.compactMap(read).map { source in var named = source; named.methodName = methodName(of: source.id, among: methods); return named }
    }, select: { id in
        guard SystemAccess.permits("input source selection"), let source = InputSources.source(id: id) else { return false }
        return TISSelectInputSource(source) == noErr
    })
    static func read(_ source: TISInputSource) -> InputSource? {
        func value<Value>(_ key: CFString) -> Value? { TISGetInputSourceProperty(source, key).flatMap { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() as? Value } }
        guard let id: String = value(kTISPropertyInputSourceID), let languages: [String] = value(kTISPropertyInputSourceLanguages) else { return nil }
        return InputSource(id: id, language: languages.first ?? "", mode: value(kTISPropertyInputModeID), name: value(kTISPropertyLocalizedName) ?? "")
    }
    static func source(id: String) -> TISInputSource? { list([kTISPropertyInputSourceID as String: id]).first }
    static func asciiLayout() -> InputSource? { TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap { read($0.takeRetainedValue()) } }
    // Read-only and for previews only: it also finds the modes of disabled input methods, which source(id:) does not.
    static func installed(id: String) -> InputSource? { list([kTISPropertyInputSourceID as String: id], includeAllInstalled: true).first.flatMap(read) }
    // Kotoeri's Romaji and Kana typing share mode IDs and names; the input method with the longest ID prefix tells them apart.
    // The prefix is plain, not dotted: Ainu's mode com.apple.inputmethod.AinuIM.Ainu belongs to com.apple.inputmethod.Ainu.
    static func methodName(of id: String, among methods: [InputSource]) -> String? {
        methods.filter { id.hasPrefix($0.id) }.max { $0.id.count < $1.id.count }?.name
    }
    private static func list(_ filter: [String: Any], includeAllInstalled: Bool = false) -> [TISInputSource] {
        // macOS may return nil (not an empty array) when nothing matches.
        TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource] ?? []
    }
}
