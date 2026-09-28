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
