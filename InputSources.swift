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
