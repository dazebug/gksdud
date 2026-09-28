import Foundation

// The UI language resolved from CFBundleLocalizations. Korean is the development language: its text is every key, so it has no table.
enum AppLanguage {
    static let current = resolve(localizations: Bundle.main.localizations, preferred: Bundle.main.preferredLocalizations)
    // The UI language without the region, so names match the Taiwan-worded zh-Hant table (zh-Hant_HK would say 繁體廣東話, not 繁體粵語).
    static let locale = Locale(identifier: current)
    // The bare binary has no localizations and prefers "en", yet it shows the Korean keys.
    static func resolve(localizations: [String], preferred: [String]) -> String { localizations.isEmpty ? "ko" : preferred.first ?? "ko" }
    static func name(of tag: String) -> String { locale.localizedString(forIdentifier: tag) ?? tag }
}
