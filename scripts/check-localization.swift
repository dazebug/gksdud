import Foundation

// build.sh runs this before packaging. Errors are faults that break users at runtime or blind the gates; everything a
// maintainer does in normal work (new Korean text, a forgotten wrap, a README edit) is a warning unless --strict is given.

struct Diagnostic: Equatable {
    let rule: String, file: String, line: Int, column: Int, message: String
    var isError: Bool { rule.hasPrefix("E") }
    var text: String { "\(file):\(line):\(column): \(isError ? "error" : "warning"): \(message)" }
}
struct Position: Hashable { let line: Int, column: Int }
// A literal's own text, without its interpolations. Raw strings record both the # column and the quote column.
struct Literal: Equatable { let line: Int, columns: [Int], endLine: Int, text: String, defaultValue: Bool }
struct Lexed { var literals: [Literal] = [], markers: [Position] = [], nsLocalizedString: [Position] = [] }
enum Byte {
    static let newline = UInt8(ascii: "\n"), space = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), carriageReturn = UInt8(ascii: "\r"), quote = UInt8(ascii: "\""), hash = UInt8(ascii: "#")
    static let backslash = UInt8(ascii: "\\"), slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), open = UInt8(ascii: "("), close = UInt8(ascii: ")"), colon = UInt8(ascii: ":")
}

// Just enough of Swift's lexer to find string literals where swiftc does, with the same 1-based UTF-8 byte columns.
struct Lexer {
    let bytes: [UInt8]
    var i = 0, line = 1, lineStart = 0, lexed = Lexed()
    init(_ source: String) { bytes = Array(source.utf8) }
    var column: Int { i - lineStart + 1 }
    func at(_ offset: Int) -> UInt8 { i + offset < bytes.count ? bytes[i + offset] : 0 }
    func hashes(_ count: Int, at offset: Int) -> Bool { (0..<count).allSatisfy { at(offset + $0) == Byte.hash } }
    func isWord(_ byte: UInt8) -> Bool { byte == UInt8(ascii: "_") || (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) }
    mutating func newline() { i += 1; line += 1; lineStart = i }

    mutating func code(interpolation: Bool = false) {
        var depth = 0
        while i < bytes.count {
            switch bytes[i] {
            case Byte.newline: newline()
            case Byte.slash where at(1) == Byte.slash: lineComment()
            case Byte.slash where at(1) == Byte.star: blockComment()
            case Byte.quote: string(hashes: 0)
            case Byte.hash:
                var count = 0
                while at(count) == Byte.hash { count += 1 }
                if at(count) == Byte.quote { string(hashes: count) } else { i += count }
            case Byte.open: depth += 1; i += 1
            case Byte.close:
                i += 1
                if interpolation && depth == 0 { return }
                depth -= 1
            case let byte where isWord(byte):
                let start = i, position = Position(line: line, column: column)
                while i < bytes.count, isWord(bytes[i]) { i += 1 }
                if bytes[start..<i].elementsEqual("NSLocalizedString".utf8) { lexed.nsLocalizedString.append(position) }
            default: i += 1
            }
        }
    }

    mutating func lineComment() {
        let start = i, position = Position(line: line, column: column)
        while i < bytes.count, bytes[i] != Byte.newline { i += 1 }
        if String(decoding: bytes[(start + 2)..<i], as: UTF8.self).trimmingCharacters(in: .whitespaces).hasPrefix("l10n-ignore:") { lexed.markers.append(position) }
    }

    mutating func blockComment() {
        var depth = 0
        repeat {
            if at(0) == Byte.slash, at(1) == Byte.star { depth += 1; i += 2 }
            else if at(0) == Byte.star, at(1) == Byte.slash { depth -= 1; i += 2 }
            else if at(0) == Byte.newline { newline() } else { i += 1 }
        } while depth > 0 && i < bytes.count
    }

    mutating func string(hashes count: Int) {
        let start = i, startLine = line
        var columns = [column], text: [UInt8] = []
        i += count
        if count > 0 { columns.append(column) }
        let delimiter = at(1) == Byte.quote && at(2) == Byte.quote ? 3 : 1
        i += delimiter
        while i < bytes.count {
            if bytes[i] == Byte.quote, delimiter == 1 || at(1) == Byte.quote && at(2) == Byte.quote, hashes(count, at: delimiter) { i += delimiter + count; break }
            if bytes[i] == Byte.backslash, hashes(count, at: 1) {
                i += 1 + count
                if at(0) == Byte.open { i += 1; code(interpolation: true) }
                else if at(0) == Byte.newline { newline() }
                else if at(0) == UInt8(ascii: "u"), at(1) == UInt8(ascii: "{") {
                    let digits = i + 2
                    var end = digits
                    while end < bytes.count, bytes[end] != UInt8(ascii: "}"), end - digits < 8 { end += 1 }
                    if let value = UInt32(String(decoding: bytes[digits..<end], as: UTF8.self), radix: 16), let scalar = Unicode.Scalar(value) { text += Array(String(scalar).utf8) }
                    i = end + 1
                } else {
                    text.append(["n": Byte.newline, "t": Byte.tab, "r": Byte.carriageReturn, "0": 0][Character(Unicode.Scalar(at(0)))] ?? at(0)); i += 1
                }
                continue
            }
            if bytes[i] == Byte.newline {
                guard delimiter == 3 else { break }
                text.append(Byte.newline); newline(); continue
            }
            text.append(bytes[i]); i += 1
        }
        lexed.literals.append(Literal(line: startLine, columns: columns, endLine: line, text: String(decoding: text, as: UTF8.self), defaultValue: labelled("defaultValue", before: start)))
    }

    // String(localized: "key", defaultValue: "한국어") extracts the default at the key's position, so the default is not unwrapped text.
    func labelled(_ label: String, before index: Int) -> Bool {
        var j = index - 1
        while j >= 0, [Byte.space, Byte.tab, Byte.newline].contains(bytes[j]) { j -= 1 }
        guard j >= 0, bytes[j] == Byte.colon else { return false }
        j -= 1
        while j >= 0, [Byte.space, Byte.tab].contains(bytes[j]) { j -= 1 }
        let end = j + 1
        while j >= 0, isWord(bytes[j]) { j -= 1 }
        return bytes[(j + 1)..<end].elementsEqual(label.utf8)
    }
}
func lex(_ source: String) -> Lexed { var lexer = Lexer(source); lexer.code(); return lexer.lexed }

func isHangul(_ scalar: Unicode.Scalar) -> Bool {
    [0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xD7B0...0xD7FF].contains { $0.contains(scalar.value) }
}
func hasHangul(_ text: String) -> Bool { text.unicodeScalars.contains(where: isHangul) }

// printf specifiers as String(localized:) writes interpolations (%@, %lld, %lf), with the n$ positions translators may add.
// Each lists the arguments Foundation reads for it, in order: a * width, a .* precision, then the value.
struct Argument: Equatable { let position: Int?, conversion: String }
struct Specifier { let arguments: [Argument], text: String, end: Int }
func specifiers(_ text: String) -> [Specifier] {
    let scalars = Array(text.unicodeScalars)
    var result: [Specifier] = [], i = 0
    func string(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[range.clamped(to: 0..<scalars.count)])) }
    func has(_ set: String, _ index: Int) -> Bool { index < scalars.count && set.unicodeScalars.contains(scalars[index]) }
    func digits(from index: Int) -> Int { var end = index; while has("0123456789", end) { end += 1 }; return end }
    func numbered(_ index: Int) -> (position: Int?, end: Int) {
        let number = digits(from: index)
        return number > index && has("$", number) ? (Int(string(index..<number)), number + 1) : (nil, index)
    }
    while i < scalars.count {
        guard scalars[i] == "%" else { i += 1; continue }
        if has("%", i + 1) { i += 2; continue }
        let value = numbered(i + 1)
        var j = value.end, arguments: [Argument] = []
        // Foundation's format parser has no ' flag; it prints %' as text.
        while has("-+ #0", j) { j += 1 }
        if has("*", j) { let width = numbered(j + 1); arguments.append(Argument(position: width.position, conversion: "*")); j = width.end } else { j = digits(from: j) }
        if has(".", j), has("*", j + 1) { let precision = numbered(j + 2); arguments.append(Argument(position: precision.position, conversion: ".*")); j = precision.end }
        else if has(".", j) { j = digits(from: j + 1) }
        let length = ["hh", "ll", "h", "l", "q", "L", "z", "t", "j"].first { string(j..<(j + 2)).hasPrefix($0) } ?? ""
        j += length.count
        guard has("@diuoxXDUOfFeEgGaAcCsSpnP", j) else { i += 1; continue }
        // Foundation reads %D, %U and %O like %d, %u and %o, not as the long that printf(3) documents.
        let conversion = length + (["D": "d", "U": "u", "O": "o"][String(scalars[j])] ?? String(scalars[j]))
        result.append(Specifier(arguments: arguments + [Argument(position: value.position, conversion: conversion)], text: string(i..<(j + 1)), end: j + 1))
        i = j + 1
    }
    return result
}
func formatMismatch(_ source: String, _ translation: String, as names: (String, String) = ("in the original", "in the translation")) -> String? {
    func signature(_ text: String) -> (arguments: [Int: String], count: Int, mixed: Bool) {
        var arguments: [Int: String] = [:], next = 1, positional = false, sequential = false
        let found = specifiers(text).flatMap(\.arguments)
        for argument in found {
            if let position = argument.position { arguments[position] = argument.conversion; positional = true }
            else { arguments[next] = argument.conversion; next += 1; sequential = true }
        }
        return (arguments, found.count, positional && sequential)
    }
    let a = signature(source), b = signature(translation)
    guard a.count != b.count || a.arguments != b.arguments || a.mixed || b.mixed else { return nil }
    func list(_ text: String) -> String { let found = specifiers(text).map(\.text); return found.isEmpty ? "none" : found.joined(separator: " ") }
    return "\(list(source)) \(names.0), \(list(translation)) \(names.1)"
}
// A case particle's form depends on the final sound of the word before it, which a placeholder hides (F19은 is wrong).
func particle(after text: String) -> String? {
    let scalars = Array(text.unicodeScalars)
    for specifier in specifiers(text) {
        for particle in ["으로", "은", "는", "이", "가", "을", "를", "과", "와", "로"] {
            let end = specifier.end + particle.unicodeScalars.count
            guard end <= scalars.count, String(String.UnicodeScalarView(scalars[specifier.end..<end])) == particle else { continue }
            if end == scalars.count || !isHangul(scalars[end]) { return particle }
        }
    }
    return nil
}

// The bundle finds a key only under its exact scalars, but String's == takes an NFD 활성화 for the NFC one.
struct Key: Hashable { let scalars: [Unicode.Scalar]; init(_ text: String) { scalars = Array(text.unicodeScalars) } }
struct TableEntry: Equatable { let key: String, value: String, line: Int, column: Int }
enum TableLine { case blank, comment, entry(key: String, value: String, column: Int), invalid(column: Int, message: String) }
func tableLine(_ line: String) -> TableLine {
    let bytes = Array(line.utf8)
    var i = 0
    func skipSpace() { while i < bytes.count, [Byte.space, Byte.tab, Byte.carriageReturn].contains(bytes[i]) { i += 1 } }
    // Decoded by the same parser the bundle uses, so \n, \" and \U escapes match what the app looks up.
    func quoted() -> String? {
        guard i < bytes.count, bytes[i] == Byte.quote else { return nil }
        var j = i + 1
        while j < bytes.count, bytes[j] != Byte.quote { j += bytes[j] == Byte.backslash ? 2 : 1 }
        guard j < bytes.count, let text = (try? PropertyListSerialization.propertyList(from: Data(bytes[i...j]), format: nil)) as? String else { return nil }
        i = j + 1
        return text
    }
    skipSpace()
    guard i < bytes.count else { return .blank }
    let start = i + 1, trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/*") {
        return trimmed.count >= 4 && trimmed.hasSuffix("*/") && !trimmed.dropFirst(2).dropLast(2).contains("*/") ? .comment : .invalid(column: start, message: "a comment must open and close on its own line")
    }
    guard let key = quoted() else { return .invalid(column: i + 1, message: "expected \"key\" = \"value\"; on one line") }
    skipSpace()
    guard i < bytes.count, bytes[i] == UInt8(ascii: "=") else { return .invalid(column: i + 1, message: "expected = after the key") }
    i += 1; skipSpace()
    guard let value = quoted() else { return .invalid(column: i + 1, message: "expected the quoted translation after =") }
    skipSpace()
    guard i < bytes.count, bytes[i] == UInt8(ascii: ";") else { return .invalid(column: i + 1, message: "missing ; after the translation") }
    i += 1; skipSpace()
    guard i == bytes.count else { return .invalid(column: i + 1, message: bytes[i] == Byte.quote ? "only one entry is allowed per line" : "unexpected text after the entry") }
    return .entry(key: key, value: value, column: start)
}
func parseTable(path: String, data: Data) -> (entries: [TableEntry], diagnostics: [Diagnostic]) {
    func at(_ rule: String, _ line: Int, _ column: Int, _ message: String) -> Diagnostic { Diagnostic(rule: rule, file: path, line: line, column: column, message: message) }
    guard var text = String(data: data, encoding: .utf8) else { return ([], [at("E2", 1, 1, "the table is not UTF-8; check it with plutil -lint \(path)")]) }
    var entries: [TableEntry] = [], diagnostics: [Diagnostic] = [], seen: [Key: Int] = [:]
    do {
        guard try PropertyListSerialization.propertyList(from: data, format: nil) is [String: String] else { throw CocoaError(.propertyListReadCorrupt) }
    } catch {
        let reason = ((error as NSError).userInfo["kCFPropertyListOldStyleParsingError"] as? NSError ?? error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "\(error)"
        diagnostics.append(at("E2", 1, 1, "the bundle cannot load this table (\(reason)), so none of its translations would show; check it with plutil -lint \(path)"))
    }
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    for (index, content) in text.components(separatedBy: "\n").enumerated() {
        switch tableLine(content) {
        case .blank, .comment: continue
        case let .invalid(column, message): diagnostics.append(at("E3", index + 1, column, message))
        case let .entry(key, value, column):
            if let first = seen[Key(key)] {
                diagnostics.append(at("E4", index + 1, column, "duplicate key \"\(escaped(key))\" (first on line \(first)); the bundle would silently keep only the last one")); continue
            }
            seen[Key(key)] = index + 1
            if value.isEmpty { diagnostics.append(at("E5", index + 1, column, "empty translation for \"\(escaped(key))\"")) }
            entries.append(TableEntry(key: key, value: value, line: index + 1, column: column))
        }
    }
    return (entries, diagnostics)
}

struct Extracted { var key: String, line: Int, column: Int, comment = "", table = "Localizable", value: String? = nil
    var text: String { value ?? key }
}
struct Source { var path: String, text: String, extracted: [Extracted]?
    var isTest: Bool { path.hasSuffix("Tests.swift") }
}
struct Project {
    var sources: [Source] = [], stringsdata = "strings"
    var plistPath = "Info.plist", plist = Data()
    var resources = "Resources", lprojs: [String] = [], tables: [String: Data] = [:]
    var readme: (path: String, data: Data)? = nil, translations: [(path: String, text: String)] = []
}
struct Report { var diagnostics: [Diagnostic] = [], summary = "", missing: [(language: String, count: Int)] = [] }
// The .stringsdata JSON that swiftc -emit-localized-strings writes for every source.
struct StringsData: Decodable {
    struct Entry: Decodable { struct Location: Decodable { let startingLine: Int, startingColumn: Int }; let key: String, comment: String?, value: String?, location: Location }
    let source: String?, tables: [String: [Entry]]
    var extracted: [Extracted] {
        tables.flatMap { table, entries in entries.map { Extracted(key: $0.key, line: $0.location.startingLine, column: $0.location.startingColumn, comment: $0.comment ?? "", table: table, value: $0.value) } }
            .sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }
}

func check(_ project: Project) -> Report {
    var diagnostics: [Diagnostic] = [], keys: [Key] = [], uses: [Key: [(file: String, entry: Extracted)]] = [:], unwrapped = 0
    for source in project.sources {
        var found: [Diagnostic] = []
        func at(_ rule: String, _ line: Int, _ column: Int, _ message: String) { found.append(Diagnostic(rule: rule, file: source.path, line: line, column: column, message: message)) }
        guard let extracted = source.extracted else {
            let name = ((source.path as NSString).lastPathComponent as NSString).deletingPathExtension
            at("E1", 1, 1, "\(project.stringsdata)/\(name).stringsdata is missing or unreadable, so String(localized:) extraction did not run; it needs Swift 5.9 or later and -emit-localized-strings on the compile")
            diagnostics += found; continue
        }
        for entry in extracted {
            if source.isTest { at("W11", entry.line, entry.column, "tests compare with the Korean source text; String(localized:) here adds a key that needs translating"); continue }
            if entry.table != "Localizable" { at("W8", entry.line, entry.column, "String(localized:) uses the table \(entry.table); only Localizable is translated, so this text stays Korean"); continue }
            // Every use of a key shares one translation, which cannot match two different sets of specifiers.
            let key = Key(entry.key)
            if let first = uses[key]?.first, let mismatch = formatMismatch(first.entry.text, entry.text, as: ("at \(first.file):\(first.entry.line)", "here")) {
                at("E6", entry.line, entry.column, "format specifiers differ between the uses of \"\(escaped(entry.key))\": \(mismatch); no single translation can match both")
            }
            if uses[key] == nil { keys.append(key) }
            uses[key, default: []].append((source.path, entry))
            if entry.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.text.count <= 6 || !specifiers(entry.text).isEmpty {
                at("W4", entry.line, entry.column, "\"\(escaped(entry.text))\" needs a comment: naming the UI element and what each placeholder holds")
            }
            if let particle = particle(after: entry.text) {
                at("W6", entry.line, entry.column, "the particle \(particle) follows a placeholder in \"\(escaped(entry.text))\"; its form depends on the inserted word, so put a fixed word before it, as in \"%@ 키는\"")
            }
        }
        if !source.isTest {
            let lexed = lex(source.text), wrapped = Set(extracted.map { Position(line: $0.line, column: $0.column) })
            let open = lexed.literals.filter { literal in hasHangul(literal.text) && !literal.defaultValue && !literal.columns.contains { wrapped.contains(Position(line: literal.line, column: $0)) } }
            let marked = Set(lexed.markers.map(\.line)), openLines = Set(open.flatMap { Array($0.line...$0.endLine) })
            for literal in open where !(literal.line...literal.endLine).contains(where: marked.contains) {
                unwrapped += 1
                at("W5", literal.line, literal.columns[0], "Korean text is not localized. Wrap it in String(localized:comment:), or add // l10n-ignore: <reason> if it is data.")
            }
            for marker in lexed.markers where !openLines.contains(marker.line) { at("W9", marker.line, marker.column, "l10n-ignore marker on a line without unlocalized Korean text; remove it") }
            for use in lexed.nsLocalizedString { at("W10", use.line, use.column, "NSLocalizedString is not extracted, so its text is never translated; use String(localized:comment:)") }
        }
        diagnostics += found.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }

    let (listed, plistDiagnostics) = checkPlist(project)
    diagnostics += plistDiagnostics
    let languages = listed.filter { project.tables[$0] != nil } + project.tables.keys.filter { !listed.contains($0) }.sorted()
    var counts: [String] = [], missing: [(language: String, count: Int)] = []
    for language in languages {
        let path = "\(project.resources)/\(language).lproj/Localizable.strings", data = project.tables[language]!
        let (entries, tableDiagnostics) = parseTable(path: path, data: data)
        diagnostics += tableDiagnostics
        guard String(data: data, encoding: .utf8) != nil else { counts.append("\(language) unreadable"); continue }
        let present = Set(entries.map { Key($0.key) }), absent = keys.filter { !present.contains($0) }
        for key in absent {
            let use = uses[key]![0]
            diagnostics.append(Diagnostic(rule: "W1", file: use.file, line: use.entry.line, column: use.entry.column,
                message: "\(language): missing translation \"\(escaped(use.entry.key))\", shown in Korean; check-localization --missing \(language) prints the entries to add"))
        }
        var stale = 0
        for entry in entries {
            func at(_ rule: String, _ message: String) { diagnostics.append(Diagnostic(rule: rule, file: path, line: entry.line, column: entry.column, message: message)) }
            let texts = (uses[Key(entry.key)] ?? []).map { $0.entry.text }
            if texts.isEmpty { stale += 1; at("W2", "\(language): stale translation \"\(escaped(entry.key))\" is no longer used in code") }
            if hasHangul(entry.value) { at("W3", "\(language): the translation of \"\(escaped(entry.key))\" contains Korean text") }
            // Nothing looks up a stale entry, so it has no text to compare; W2 reports it without stopping the build.
            let mismatches = texts.compactMap { formatMismatch($0, entry.value) }
            for (index, mismatch) in mismatches.enumerated() where !mismatches[..<index].contains(mismatch) { at("E6", "format specifiers differ for \"\(escaped(entry.key))\": \(mismatch)") }
        }
        counts.append("\(language) \(absent.count) missing \(stale) stale")
        missing.append((language, absent.count))
    }

    if let readme = project.readme {
        let marker = "<!-- translated-from: \((readme.path as NSString).lastPathComponent) sha256=\(sha256(readme.data)) -->"
        for translation in project.translations where translation.text.components(separatedBy: .newlines).first != marker {
            let stale = translation.text.hasPrefix("<!-- translated-from:")
            diagnostics.append(Diagnostic(rule: "W7", file: translation.path, line: 1, column: 1, message: stale
                ? "\(readme.path) changed after this translation; update the translation, then set its first line to \(marker)"
                : "the first line must be \(marker), which records the \(readme.path) this translation follows"))
        }
    }
    let errors = diagnostics.filter(\.isError).count
    let summary = (["localization: \(keys.count) keys"] + counts + ["\(unwrapped) unwrapped", "\(errors) errors, \(diagnostics.count - errors) warnings"]).joined(separator: "; ")
    return Report(diagnostics: diagnostics, summary: summary, missing: missing)
}

// Info.plist is the single source of UI languages: every listed translation needs a table, and every lproj must be listed.
func checkPlist(_ project: Project) -> (listed: [String], diagnostics: [Diagnostic]) {
    let lines = String(decoding: project.plist, as: UTF8.self).components(separatedBy: "\n")
    func at(_ key: String?, _ message: String) -> Diagnostic {
        Diagnostic(rule: "E7", file: project.plistPath, line: (key.flatMap { key in lines.firstIndex { $0.contains("<key>\(key)</key>") } } ?? 0) + 1, column: 1, message: message)
    }
    guard let plist = (try? PropertyListSerialization.propertyList(from: project.plist, format: nil)) as? [String: Any] else { return ([], [at(nil, "cannot read \(project.plistPath) as a property list")]) }
    guard let development = plist["CFBundleDevelopmentRegion"] as? String else { return ([], [at(nil, "CFBundleDevelopmentRegion is missing")]) }
    let listed = plist["CFBundleLocalizations"] as? [String] ?? [], key = "CFBundleLocalizations"
    var diagnostics: [Diagnostic] = []
    if listed.first != development {
        diagnostics.append(at(key, "CFBundleLocalizations must start with the development region \(development); otherwise unsupported system languages get another language's Locale"))
    }
    for language in listed where language != development && project.tables[language] == nil {
        diagnostics.append(at(key, "\(language) is listed in CFBundleLocalizations, but \(project.resources)/\(language).lproj/Localizable.strings does not exist"))
    }
    for language in project.lprojs where !listed.contains(language) {
        diagnostics.append(at(key, "\(project.resources)/\(language).lproj is not listed in CFBundleLocalizations; add \(language) or remove the folder"))
    }
    return (listed, diagnostics)
}

// One "/* file:line comment */" line and one "key" = "key"; line per entry. The Korean value keeps the table valid, and W3
// keeps flagging it until someone translates it.
func missingEntries(sources: [Source], table: [TableEntry]) -> String {
    let present = Set(table.map { Key($0.key) })
    var order: [Key] = [], uses: [Key: [(file: String, entry: Extracted)]] = [:]
    for source in sources.sorted(by: { $0.path < $1.path }) where !source.isTest {
        for entry in (source.extracted ?? []).sorted(by: { ($0.line, $0.column) < ($1.line, $1.column) }) where entry.table == "Localizable" {
            let key = Key(entry.key)
            guard !present.contains(key) else { continue }
            if uses[key] == nil { order.append(key) }
            uses[key, default: []].append((source.path, entry))
        }
    }
    var output = "", group = ""
    for key in order {
        let sites = uses[key]!, comment = sites.first(where: { !$0.entry.comment.isEmpty })?.entry.comment ?? ""
        if !output.isEmpty && sites[0].file != group { output += "\n" }
        group = sites[0].file
        let note = ([sites.map { "\($0.file):\($0.entry.line)" }.joined(separator: ", ")] + (comment.isEmpty ? [] : [comment])).joined(separator: " ")
        output += "/* \(note.replacingOccurrences(of: "*/", with: "* /").replacingOccurrences(of: "\n", with: " ")) */\n\"\(escaped(sites[0].entry.key))\" = \"\(escaped(sites[0].entry.text))\";\n"
    }
    return output
}

// Writes text the way a .strings file quotes it; messages use the same form.
func escaped(_ text: String) -> String {
    text.unicodeScalars.map { scalar -> String in
        switch scalar {
        case "\\": return "\\\\"
        case "\"": return "\\\""
        case "\n": return "\\n"
        case "\t": return "\\t"
        case "\r": return "\\r"
        default: return String(scalar)
        }
    }.joined()
}

// Foundation has no SHA-256, and the tool stays Foundation-only; --self-test checks the FIPS 180-4 test vectors.
func sha256(_ data: Data) -> String {
    let k = """
        428a2f98 71374491 b5c0fbcf e9b5dba5 3956c25b 59f111f1 923f82a4 ab1c5ed5 d807aa98 12835b01 243185be 550c7dc3 72be5d74 80deb1fe 9bdc06a7 c19bf174
        e49b69c1 efbe4786 0fc19dc6 240ca1cc 2de92c6f 4a7484aa 5cb0a9dc 76f988da 983e5152 a831c66d b00327c8 bf597fc7 c6e00bf3 d5a79147 06ca6351 14292967
        27b70a85 2e1b2138 4d2c6dfc 53380d13 650a7354 766a0abb 81c2c92e 92722c85 a2bfe8a1 a81a664b c24b8b70 c76c51a3 d192e819 d6990624 f40e3585 106aa070
        19a4c116 1e376c08 2748774c 34b0bcb5 391c0cb3 4ed8aa4a 5b9cca4f 682e6ff3 748f82ee 78a5636f 84c87814 8cc70208 90befffa a4506ceb bef9a3f7 c67178f2
        """.split(whereSeparator: \.isWhitespace).map { UInt32($0, radix: 16)! }
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var bytes = [UInt8](data)
    let bits = UInt64(bytes.count) * 8
    bytes.append(0x80)
    while bytes.count % 64 != 56 { bytes.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
    func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { x >> n | x << (32 - n) }
    for chunk in stride(from: 0, to: bytes.count, by: 64) {
        var w = (0..<16).map { t in (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[chunk + 4 * t + $1]) } }
        for t in 16..<64 {
            let s0 = rotate(w[t - 15], 7) ^ rotate(w[t - 15], 18) ^ w[t - 15] >> 3, s1 = rotate(w[t - 2], 17) ^ rotate(w[t - 2], 19) ^ w[t - 2] >> 10
            w.append(w[t - 16] &+ s0 &+ w[t - 7] &+ s1)
        }
        var v = h
        for t in 0..<64 {
            let s1 = rotate(v[4], 6) ^ rotate(v[4], 11) ^ rotate(v[4], 25), choice = v[4] & v[5] ^ ~v[4] & v[6]
            let s0 = rotate(v[0], 2) ^ rotate(v[0], 13) ^ rotate(v[0], 22), majority = v[0] & v[1] ^ v[0] & v[2] ^ v[1] & v[2]
            let t1 = v[7] &+ s1 &+ choice &+ k[t] &+ w[t]
            v = [t1 &+ s0 &+ majority, v[0], v[1], v[2], v[3] &+ t1, v[4], v[5], v[6]]
        }
        h = zip(h, v).map { $0 &+ $1 }
    }
    return h.map { String(format: "%08x", $0) }.joined()
}

func annotation(_ diagnostic: Diagnostic) -> String {
    func data(_ text: String) -> String { text.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "\r", with: "%0D").replacingOccurrences(of: "\n", with: "%0A") }
    func property(_ text: String) -> String { data(text).replacingOccurrences(of: ":", with: "%3A").replacingOccurrences(of: ",", with: "%2C") }
    return "::\(diagnostic.isError ? "error" : "warning") file=\(property(diagnostic.file)),line=\(diagnostic.line),col=\(diagnostic.column)::\(data(diagnostic.message))"
}
func exitStatus(_ diagnostics: [Diagnostic], strict: Bool) -> Int32 { diagnostics.contains(where: \.isError) || strict && !diagnostics.isEmpty ? 1 : 0 }

// Reads the real files; the checks above never touch the file system, so --self-test runs them on in-memory fixtures.
func load(sources paths: [String], stringsdata: String, plist: String, resources: String, readme: String?) throws -> Project {
    let manager = FileManager.default
    var project = Project(stringsdata: stringsdata, plistPath: plist, plist: try Data(contentsOf: URL(fileURLWithPath: plist)), resources: resources)
    project.sources = try paths.map { path in
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let data = manager.contents(atPath: (stringsdata as NSString).appendingPathComponent("\(name).stringsdata"))
        return Source(path: path, text: try String(contentsOfFile: path, encoding: .utf8), extracted: data.flatMap { try? JSONDecoder().decode(StringsData.self, from: $0) }?.extracted)
    }
    for folder in try manager.contentsOfDirectory(atPath: resources).sorted() where folder.hasSuffix(".lproj") {
        let language = String(folder.dropLast(".lproj".count))
        project.lprojs.append(language)
        project.tables[language] = manager.contents(atPath: "\(resources)/\(folder)/Localizable.strings")
    }
    if let readme {
        let directory = (readme as NSString).deletingLastPathComponent, name = (readme as NSString).lastPathComponent, stem = (name as NSString).deletingPathExtension
        project.readme = (readme, try Data(contentsOf: URL(fileURLWithPath: readme)))
        for file in try manager.contentsOfDirectory(atPath: directory.isEmpty ? "." : directory).sorted() where file != name && file.hasPrefix(stem + ".") && file.hasSuffix(".md") {
            let path = (directory as NSString).appendingPathComponent(file)
            project.translations.append((path, try String(contentsOfFile: path, encoding: .utf8)))
        }
    }
    return project
}
func loadStringsdata(_ directory: String) throws -> [Source] {
    try FileManager.default.contentsOfDirectory(atPath: directory).sorted().filter { $0.hasSuffix(".stringsdata") }.map { file in
        let data = try JSONDecoder().decode(StringsData.self, from: Data(contentsOf: URL(fileURLWithPath: (directory as NSString).appendingPathComponent(file))))
        return Source(path: data.source.map { ($0 as NSString).lastPathComponent } ?? (file as NSString).deletingPathExtension + ".swift", text: "", extracted: data.extracted)
    }
}

func selfTest() -> Bool {
    var failures = 0
    func expect(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        if !condition { failures += 1; fputs("FAIL: \(file):\(line) \(message())\n", stderr) }
    }
    func section(_ name: String, _ body: () -> Void) { let before = failures; body(); if failures == before { print("PASS: \(name)") } }
    func found(_ diagnostics: [Diagnostic]) -> [String] { diagnostics.map { "\($0.rule) \($0.file):\($0.line):\($0.column)" }.sorted() }
    func plist(_ languages: [String], development: String = "ko") -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleDevelopmentRegion</key><string>\(development)</string>
        <key>CFBundleLocalizations</key><array>\(languages.map { "<string>\($0)</string>" }.joined())</array>
        </dict></plist>
        """.utf8)
    }
    func fixture(_ sources: [Source] = [], tables: [String: String] = [:], languages: [String]? = nil) -> Project {
        var project = Project()
        project.sources = sources; project.lprojs = tables.keys.sorted(); project.tables = tables.mapValues { Data($0.utf8) }
        project.plist = plist(languages ?? ["ko"] + tables.keys.sorted())
        return project
    }
    // Two spellings of 활성화 that String's == calls equal and the bundle tells apart.
    let nfc = "활성화".precomposedStringWithCanonicalMapping, nfd = nfc.decomposedStringWithCanonicalMapping

    section("lexer skips comments and nested comments, and reads escapes, \"#\", raw, multi-line and URL literals and nested interpolations") {
        let lexed = lex(##"""
            // 주석 속 "한글"은 무시합니다
            /* 바깥 /* 안쪽 */ "여전히 주석" */
            let a = "따옴표 \"안\" 끝 \u{D55C}"
            let depth = trimmed.prefix(while: { $0 == "#" }).count
            let b = #"로우 "문자열""#, c = ##"이중 "# 로우"##
            let d = """
                여러 줄 "따옴표"
                """
            let url = "https://github.com/codingnoye/gksdud" // 링크
            let e = "상태 \(a ? "한" : "영")"
            """##)
        let literals = lexed.literals.sorted { ($0.line, $0.columns[0]) < ($1.line, $1.columns[0]) }
        let shown = literals.map { "\($0.line):\($0.columns.map(String.init).joined(separator: "/")) \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
        expect(shown == ["3:9 따옴표 \"안\" 끝 한", "4:43 #", "5:9/10 로우 \"문자열\"", "5:37/39 이중 \"# 로우", "6:9 여러 줄 \"따옴표\"",
            "9:11 https://github.com/codingnoye/gksdud", "10:9 상태", "10:23 한", "10:31 영"], "lexed \(shown)")
        expect(literals.first(where: { $0.line == 6 })?.endLine == 8, "a multi-line literal must end on its closing line")
    }

    section("literal positions match swiftc extraction: UTF-8 byte columns, raw and multi-line strings, calls nested in interpolations") {
        // The source and the .stringsdata that swiftc -emit-localized-strings wrote for it.
        let probe = ###"""
            import Foundation
            let name = "x"
            let n = 3
            let d = 2.5
            let s1 = String(localized: "한글 문장 \(name) 그리고 \(n)", comment: "c1")
            let s2 = String(localized: "한국어"); let s3 = String(localized: "두번째 한국어 \(d)", comment: "second on line")
            let s4 = String(localized: "퍼센트 % 기호", comment: "pct")
            let s5 = String(localized: "semantic.key", defaultValue: "기본값 \(name)", comment: "def")
            let s6 = String(localized: "다른 테이블", table: "Other", comment: "tbl")
            let s7 = "바깥 \(n > 1 ? String(localized: "안쪽") : "영")"
            let s8 = String(localized: "줄\n바꿈 \"따옴표\"", comment: "esc")
            let s9 = String(localized: """
            여러 줄 \(name)
            문장
            """, comment: "multi")
            let s10 = String(localized: "\(name) 탭, 업데이트 가능", comment: "tab")
            let s11 = NSLocalizedString("엔에스", comment: "ns")
            let s12 = String(localized: #"로우 "문자열""#, comment: "raw")
            let s13 = String(localized: "%@은 이상", comment: "manual percent")
            let s14 = String(localized: "탭\t문자 \\ 백슬래시 \u{1F600}", comment: "escapes")
            let s15 = String(localized: ##"이중 로우 \##(name) 값"##, comment: "raw interp")
            let s16 = String(localized: "값 \(d, specifier: "%.1f")", comment: "specifier")
            """###
        let json = #"{"tables":{"Localizable":[{"comment":"c1","key":"한글 문장 %@ 그리고 %lld","location":{"startingColumn":28,"startingLine":5}},{"comment":"","key":"한국어","location":{"startingColumn":28,"startingLine":6}},{"comment":"second on line","key":"두번째 한국어 %lf","location":{"startingColumn":69,"startingLine":6}},{"comment":"pct","key":"퍼센트 % 기호","location":{"startingColumn":28,"startingLine":7}},{"comment":"def","key":"semantic.key","location":{"startingColumn":28,"startingLine":8},"value":"기본값 %@"},{"comment":"","key":"안쪽","location":{"startingColumn":46,"startingLine":10}},{"comment":"esc","key":"줄\n바꿈 \"따옴표\"","location":{"startingColumn":28,"startingLine":11}},{"comment":"multi","key":"여러 줄 %@\n문장","location":{"startingColumn":28,"startingLine":12}},{"comment":"tab","key":"%@ 탭, 업데이트 가능","location":{"startingColumn":29,"startingLine":16}},{"comment":"raw","key":"로우 \"문자열\"","location":{"startingColumn":29,"startingLine":18}},{"comment":"manual percent","key":"%@은 이상","location":{"startingColumn":29,"startingLine":19}},{"comment":"escapes","key":"탭\t문자 \\ 백슬래시 😀","location":{"startingColumn":29,"startingLine":20}},{"comment":"raw interp","key":"이중 로우 %@ 값","location":{"startingColumn":29,"startingLine":21}},{"comment":"specifier","key":"값 %.1f","location":{"startingColumn":29,"startingLine":22}}],"Other":[{"comment":"tbl","key":"다른 테이블","location":{"startingColumn":28,"startingLine":9}}]},"version":1}"#
        let extracted = (try? JSONDecoder().decode(StringsData.self, from: Data(json.utf8)))?.extracted ?? []
        expect(extracted.count == 15 && extracted.contains { $0.table == "Other" } && extracted.contains { $0.value == "기본값 %@" }, "the .stringsdata fixture must decode")
        let report = check(fixture([Source(path: "Probe.swift", text: probe, extracted: extracted)]))
        let expected = ["W4 Probe.swift:6:28", "W4 Probe.swift:10:46", "W5 Probe.swift:10:10", "W5 Probe.swift:10:58", "W5 Probe.swift:17:29", "W6 Probe.swift:19:29", "W8 Probe.swift:9:28", "W10 Probe.swift:17:11"]
        expect(found(report.diagnostics) == expected.sorted(), "\(found(report.diagnostics))")
        let columns = lex(probe).literals.filter { $0.line == 6 && hasHangul($0.text) }.map { $0.columns[0] }.sorted()
        expect(columns == [28, 69], "the second literal after Hangul must sit at byte column 69, as swiftc reports, not \(columns)")
    }

    section("extracted positions count as wrapped, nested literals do not, and l10n-ignore markers suppress or go stale") {
        let source = #"""
            let a = String(localized: "번역됨", comment: "Wrapped label")
            let b = String(localized: "현재 \(x ? "한" : "영")", comment: "Outer label")
            let c = "데이터" // l10n-ignore: stored value
            let d = 1 // l10n-ignore: nothing to ignore
            let e = "그냥 한국어"
            let f = String(localized: "번역됨", comment: "Wrapped again") // l10n-ignore: stale after wrapping
            let g = String(localized: "semantic.key", defaultValue: "기본 문구", comment: "Hatch")
            let h = """
                데이터 줄
                """ // l10n-ignore: fixture data
            """#
        let extracted = [Extracted(key: "번역됨", line: 1, column: 27, comment: "Wrapped label"), Extracted(key: "현재 %@", line: 2, column: 27, comment: "Outer label"),
            Extracted(key: "번역됨", line: 6, column: 27, comment: "Wrapped again"), Extracted(key: "semantic.key", line: 7, column: 27, comment: "Hatch", value: "기본 문구")]
        let report = check(fixture([Source(path: "Menu.swift", text: source, extracted: extracted)]))
        let expected = ["W5 Menu.swift:2:41", "W5 Menu.swift:2:49", "W5 Menu.swift:5:9", "W9 Menu.swift:4:11", "W9 Menu.swift:6:66"]
        expect(found(report.diagnostics) == expected.sorted(), "\(found(report.diagnostics))")
        expect(report.summary.contains("; 3 unwrapped;"), report.summary)
    }

    section("format specifiers: positions, %%, length modifiers, * widths and precisions, Foundation's conversions and counts") {
        func conversions(_ text: String) -> [String] { specifiers(text).flatMap(\.arguments).map(\.conversion) }
        expect(formatMismatch("%@ %lld", "%2$lld %1$@") == nil, "reordered positional specifiers must match")
        expect(formatMismatch("%@ %lld", "%lld %@") != nil, "swapped conversions must not match")
        expect(conversions("100%% %@") == ["@"] && formatMismatch("100%% %@", "%@ 100%%") == nil, "%% must be ignored")
        expect(conversions("%lf %.1f %5lld") == ["lf", "f", "lld"] && formatMismatch("%lf", "%1$lf") == nil && formatMismatch("%lf", "%f") != nil, "the length modifier belongs to the conversion")
        expect(formatMismatch("%@ %@", "%@") != nil && formatMismatch("%@", "%@ %@") != nil, "a count mismatch must not match")
        expect(specifiers("50% 할인").isEmpty && formatMismatch("%@", "%2$@ %@") != nil, "a lone % is text, and mixed positional forms do not match")
        expect(conversions("%*d") == ["*", "d"] && conversions("%-*.*lld") == ["*", ".*", "lld"], "a * width and a .* precision read an int argument each, before the value: \(conversions("%*d")) \(conversions("%-*.*lld"))")
        expect(formatMismatch("%@", "%@ %*d") != nil && formatMismatch("%lld", "%lld %.*d") != nil, "an added * width or .* precision must not match")
        expect(formatMismatch("%*d", "%2$*1$d") == nil && formatMismatch("%*d", "%1$*2$d") != nil, "a * width keeps its n$ position")
        expect(formatMismatch("%@", "%@ %D") != nil && formatMismatch("%d", "%D") == nil && formatMismatch("%lu", "%lU") == nil && formatMismatch("%o", "%O") == nil, "Foundation reads %D, %U and %O like %d, %u and %o")
        expect(formatMismatch("%@", "%@ %n") != nil && formatMismatch("%@", "%@ %P") != nil, "%n and %P read an argument")
        expect(formatMismatch("%lld %@", "%'lld %@") != nil, "Foundation prints %' as text, so the %@ after it would read the number")
    }

    section("E6 compares a translation with every use of its key, literal % text included; the uses must agree, and a stale entry gets W2 only") {
        // Whether String(localized:) formats a value without arguments is up to each user's Foundation, so "% C" stays an error.
        let extracted = [Extracted(key: "%@ 탭", line: 4, column: 9, comment: "Tab label"), Extracted(key: "CPU 100%", line: 5, column: 9, comment: "Meter label")]
        let table = "\"%@ 탭\" = \"%lld タブ\";\n\"CPU 100%\" = \"100% CPU\";\n\"tab.label\" = \"%@ タブ\";\n"
        let report = check(fixture([Source(path: "Settings.swift", text: "", extracted: extracted)], tables: ["ja": table]))
        let path = "Resources/ja.lproj/Localizable.strings"
        expect(found(report.diagnostics) == ["E6 \(path):1:1", "E6 \(path):2:1", "W2 \(path):3:1"], "\(found(report.diagnostics))")
        func shared(_ values: [String]) -> Report {
            let uses = values.enumerated().map { Extracted(key: "shared", line: $0 + 1, column: 9, comment: "Value label", value: $1) }
            return check(fixture([Source(path: "Values.swift", text: "", extracted: uses)], tables: ["ja": "\"shared\" = \"値 %@\";\n"]))
        }
        let conflict = shared(["값 %@", "값 %lld"])
        expect(found(conflict.diagnostics) == ["E6 \(path):1:1", "E6 Values.swift:2:9"], "the Int use must not pass an Int to %@: \(found(conflict.diagnostics))")
        expect(conflict.diagnostics.first { $0.file == "Values.swift" }?.message.contains("Values.swift:1") == true, "the error at the second use names the first: \(conflict.diagnostics.map(\.message))")
        expect(shared(["값 %@", "값: %@"]).diagnostics.isEmpty, "uses with the same specifiers share a translation")
    }

    section("tables: parse errors, one entry per line, duplicates by exact scalars, empty values, escapes and Hangul") {
        func table(_ text: String) -> (entries: [TableEntry], diagnostics: [Diagnostic]) { parseTable(path: "t.strings", data: Data(text.utf8)) }
        expect(table("/* main.swift:1 Menu item */\n\"a\" = \"b\";\n\n").diagnostics.isEmpty, "comments, entries and blank lines are valid")
        let semicolon = found(table("\"a\" = \"b\"\n\"c\" = \"d\";\n").diagnostics)
        expect(semicolon == ["E2 t.strings:1:1", "E3 t.strings:1:10"], "a missing semicolon: \(semicolon)")
        expect(found(table("\"a\" = \"b\"; \"c\" = \"d\";\n").diagnostics) == ["E3 t.strings:1:12"], "two entries on one line")
        expect(table("\"a\" = \"b\"; /* note */\n").diagnostics.map(\.message) == ["unexpected text after the entry"], "a comment after an entry")
        expect(found(table("\"a\" = \"b\";\n\"a\" = \"c\";\n").diagnostics) == ["E4 t.strings:2:1"], "a duplicate key")
        let spellings = table("\"\(nfc)\" = \"a\";\n\"\(nfd)\" = \"b\";\n")
        expect(spellings.diagnostics.isEmpty && spellings.entries.count == 2, "the bundle keeps NFC and NFD spellings as two keys: \(found(spellings.diagnostics))")
        expect(found(table("\"a\" = \"\";\n").diagnostics) == ["E5 t.strings:1:1"], "an empty value")
        expect(found(parseTable(path: "t.strings", data: Data([0x22, 0xE9, 0x22])).diagnostics) == ["E2 t.strings:1:1"], "a table that is not UTF-8")
        let decoded = table("\"줄\\n바꿈\" = \"改\\n行\";\n").entries
        expect(decoded.map(\.key) == ["줄\n바꿈"] && decoded.map(\.value) == ["改\n行"], "\\n must decode: \(decoded)")
        let report = check(fixture([Source(path: "Menu.swift", text: "", extracted: [Extracted(key: "줄\n바꿈", line: 1, column: 1, comment: "Label")])], tables: ["ja": "\"줄\\n바꿈\" = \"줄\\n바꿈\";\n"]))
        expect(found(report.diagnostics) == ["W3 Resources/ja.lproj/Localizable.strings:1:1"], "an escaped key matches its code key, and a Hangul value warns: \(found(report.diagnostics))")
    }

    section("keys: missing and stale by exact scalars, other tables, comments and particles after placeholders") {
        let keys = [("새 기능", "Button that opens the new feature"), ("종료", ""), ("%@ 탭", ""), ("%@은", "c"), ("%@를", "c"), ("%@와", "c"), ("%@로", "c"),
            ("%@에", "c"), ("%@입니다", "c"), ("%@ 키는", "c"), ("주석 없이도 괜찮은 긴 문장", "")]
        var extracted = keys.enumerated().map { Extracted(key: $1.0, line: $0 + 1, column: 5, comment: $1.1) }
        extracted.append(Extracted(key: "다른 표의 문구", line: 20, column: 5, comment: "Label", table: "Other"))
        let report = check(fixture([Source(path: "Settings.swift", text: "", extracted: extracted)], tables: ["ja": "\"종료\" = \"終了\";\n\"%@ 탭\" = \"%@ タブ\";\n\"오래된 문구\" = \"古い\";\n"]))
        func lines(_ rule: String) -> [Int] { report.diagnostics.filter { $0.rule == rule }.map(\.line).sorted() }
        expect(lines("W1") == [1, 4, 5, 6, 7, 8, 9, 10, 11], "missing: \(lines("W1"))")
        expect(lines("W2") == [3] && report.diagnostics.first(where: { $0.rule == "W2" })?.file == "Resources/ja.lproj/Localizable.strings", "stale: \(lines("W2"))")
        expect(lines("W8") == [20], "other table: \(lines("W8"))")
        expect(lines("W4") == [2, 3], "comments: \(lines("W4"))")
        expect(lines("W6") == [4, 5, 6, 7], "particles: \(lines("W6"))")
        expect(report.diagnostics.first(where: { $0.rule == "W1" })?.message.contains("--missing ja") == true, "a missing translation must point to --missing")
        expect(report.summary == "localization: 11 keys; ja 9 missing 1 stale; 0 unwrapped; 0 errors, 17 warnings", report.summary)
        let spelled = check(fixture([Source(path: "Menu.swift", text: "", extracted: [Extracted(key: nfd, line: 1, column: 5, comment: "Checkbox title")])], tables: ["ja": "\"\(nfc)\" = \"有効\";\n"]))
        expect(nfd == nfc && nfd.unicodeScalars.count == 8 && found(spelled.diagnostics) == ["W1 Menu.swift:1:5", "W2 Resources/ja.lproj/Localizable.strings:1:1"],
            "the bundle does not find an NFD key in code under its NFC entry: \(found(spelled.diagnostics))")
    }

    section("Info.plist and the lproj folders agree") {
        let table = "\"a\" = \"b\";\n"
        func errors(_ project: Project) -> [String] { found(check(project).diagnostics.filter { $0.rule == "E7" }) }
        expect(errors(fixture(tables: ["ja": table], languages: ["ko", "ja"])).isEmpty, "a consistent plist")
        expect(errors(fixture(tables: ["ja": table], languages: ["ja", "ko"])) == ["E7 Info.plist:4:1"], "the development region must be first")
        expect(errors(fixture(tables: ["ja": table, "zh-Hant": table], languages: ["ko", "ja"])) == ["E7 Info.plist:4:1"], "an unlisted lproj")
        expect(errors(fixture(tables: ["ja": table], languages: ["ko", "ja", "zh-Hant"])) == ["E7 Info.plist:4:1"], "a listed language without a table")
        var folder = fixture(tables: ["ja": table], languages: ["ko", "ja", "zh-Hant"]); folder.lprojs.append("zh-Hant")
        expect(errors(folder) == ["E7 Info.plist:4:1"], "a listed lproj folder without Localizable.strings")
    }

    section("README translations carry the sha256 of README.md") {
        expect(sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" && sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            && sha256(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "sha256 test vectors")
        let readme = Data("# gksdud\n".utf8)
        var project = fixture(); project.readme = ("README.md", readme)
        project.translations = [("README.ja.md", "# gksdud\n"), ("README.zh-Hant.md", "<!-- translated-from: README.md sha256=\(String(repeating: "0", count: 64)) -->\n# gksdud\n")]
        expect(found(check(project).diagnostics) == ["W7 README.ja.md:1:1", "W7 README.zh-Hant.md:1:1"], "a missing marker and a stale hash")
        project.translations = [("README.ja.md", "<!-- translated-from: README.md sha256=\(sha256(readme)) -->\n# gksdud\n")]
        expect(check(project).diagnostics.isEmpty, "a matching hash is clean")
    }

    section("--strict fails on warnings; messages are clang-style with GitHub annotations") {
        let warning = Diagnostic(rule: "W5", file: "a.swift", line: 1, column: 1, message: "m"), error = Diagnostic(rule: "E4", file: "t.strings", line: 2, column: 1, message: "m")
        expect(exitStatus([], strict: true) == 0 && exitStatus([warning], strict: false) == 0 && exitStatus([warning], strict: true) == 1 && exitStatus([error], strict: false) == 1, "exit statuses")
        expect(error.text == "t.strings:2:1: error: m" && warning.text == "a.swift:1:1: warning: m", "clang-style messages")
        expect(annotation(Diagnostic(rule: "W1", file: "a,b:c.swift", line: 3, column: 4, message: "100% done\nnext")) == "::warning file=a%2Cb%3Ac.swift,line=3,col=4::100%25 done%0Anext", "GitHub annotations")
    }

    section("a source without .stringsdata means extraction did not run") {
        let report = check(fixture([Source(path: "main.swift", text: "", extracted: nil)]))
        expect(found(report.diagnostics) == ["E1 main.swift:1:1"] && report.diagnostics[0].message.contains("Swift 5.9"), "\(found(report.diagnostics))")
    }

    section("NSLocalizedString in the app and String(localized:) in tests") {
        let app = Source(path: "Menu.swift", text: #"let x = NSLocalizedString("키", comment: "")"#, extracted: [])
        let test = Source(path: "MenuTests.swift", text: #"let y = NSLocalizedString("테스트", comment: ""); let z = "한국어""#, extracted: [Extracted(key: "테스트 문구", line: 1, column: 9, comment: "Label")])
        let report = check(fixture([app, test]))
        expect(found(report.diagnostics) == ["W10 Menu.swift:1:9", "W11 MenuTests.swift:1:9", "W5 Menu.swift:1:27"].sorted(), "\(found(report.diagnostics))")
        expect(report.summary.hasPrefix("localization: 0 keys;"), "test keys are not translation keys: \(report.summary)")
    }

    section("--missing prints paste-ready entries grouped by source file") {
        let sources = [
            Source(path: "Settings.swift", text: "", extracted: [Extracted(key: "새 기능", line: 3, column: 5, comment: "Button title"), Extracted(key: "종료", line: 9, column: 1, comment: "Quit menu item"),
                Extracted(key: "설정", line: 12, column: 1, comment: "Menu item")]),
            Source(path: "Menu.swift", text: "", extracted: [Extracted(key: "줄\n바꿈 \"따옴표\"", line: 2, column: 7, comment: "Two lines */ and a star"), Extracted(key: "새 기능", line: 5, column: 1)]),
            Source(path: "MenuTests.swift", text: "", extracted: [Extracted(key: "테스트", line: 1, column: 1)]),
        ]
        let table = "\"종료\" = \"終了\";\n"
        let output = missingEntries(sources: sources, table: parseTable(path: "ja", data: Data(table.utf8)).entries)
        expect(output == #"""
            /* Menu.swift:2 Two lines * / and a star */
            "줄\n바꿈 \"따옴표\"" = "줄\n바꿈 \"따옴표\"";
            /* Menu.swift:5, Settings.swift:3 Button title */
            "새 기능" = "새 기능";

            /* Settings.swift:12 Menu item */
            "설정" = "설정";

            """#, output)
        let pasted = parseTable(path: "ja", data: Data((table + output).utf8))
        expect(pasted.diagnostics.isEmpty && Set(pasted.entries.map(\.key)) == ["종료", "줄\n바꿈 \"따옴표\"", "새 기능", "설정"], "the entries must paste into a valid table: \(pasted)")
        expect(missingEntries(sources: sources, table: pasted.entries).isEmpty, "nothing is printed once every key is present")
        let spelled = missingEntries(sources: [Source(path: "Menu.swift", text: "", extracted: [Extracted(key: nfd, line: 1, column: 5, comment: "Checkbox title")])], table: parseTable(path: "ja", data: Data("\"\(nfc)\" = \"有効\";\n".utf8)).entries)
        expect(Array(spelled.unicodeScalars) == Array("/* Menu.swift:1 Checkbox title */\n\"\(nfd)\" = \"\(nfd)\";\n".unicodeScalars), "the NFC entry does not stand in for an NFD key: \(spelled)")
    }
    return failures == 0
}

@main
struct CheckLocalization {
    static func main() {
        setbuf(stdout, nil)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--self-test" { exit(selfTest() ? 0 : 1) }
        var options: [String: String] = [:], sources: [String] = [], strict = false, index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--strict" { strict = true }
            else if ["--stringsdata", "--info-plist", "--resources", "--readme", "--missing"].contains(argument), index + 1 < arguments.count { options[argument] = arguments[index + 1]; index += 1 }
            else if argument.hasPrefix("--") { usage() } else { sources.append(argument) }
            index += 1
        }
        guard let stringsdata = options["--stringsdata"], let resources = options["--resources"] else { usage() }
        do {
            if let language = options["--missing"] {
                let path = "\(resources)/\(language).lproj/Localizable.strings"
                let table: (entries: [TableEntry], diagnostics: [Diagnostic]) = FileManager.default.contents(atPath: path).map { parseTable(path: path, data: $0) } ?? ([], [])
                guard table.diagnostics.isEmpty else { table.diagnostics.forEach { fputs($0.text + "\n", stderr) }; exit(1) }
                print(missingEntries(sources: try loadStringsdata(stringsdata), table: table.entries), terminator: "")
                return
            }
            guard let plist = options["--info-plist"], !sources.isEmpty else { usage() }
            let report = check(try load(sources: sources, stringsdata: stringsdata, plist: plist, resources: resources, readme: options["--readme"]))
            let github = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
            for diagnostic in report.diagnostics {
                fputs(diagnostic.text + "\n", stderr)
                if github { print(annotation(diagnostic)) }
            }
            for (language, count) in report.missing where count > 0 {
                print("localization: print the \(count) missing \(language) entries with \([CommandLine.arguments[0], "--missing", language, "--stringsdata", stringsdata, "--resources", resources].map(shellQuoted).joined(separator: " "))")
            }
            print(report.summary)
            let status = exitStatus(report.diagnostics, strict: strict)
            if status != 0, !report.diagnostics.contains(where: \.isError) { fputs("localization: --strict treats these warnings as errors\n", stderr) }
            exit(status)
        } catch {
            fputs("check-localization: \(error.localizedDescription)\n", stderr); exit(1)
        }
    }
    static func usage() -> Never {
        fputs("""
            usage: check-localization --self-test
                   check-localization [--strict] --stringsdata DIR --info-plist FILE --resources DIR [--readme FILE] SWIFT_SOURCE...
                   check-localization --missing LANG --stringsdata DIR --resources DIR

            """, stderr)
        exit(2)
    }
    static func shellQuoted(_ text: String) -> String {
        text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "/._-+=".unicodeScalars.contains($0) } ? text : "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
