import Foundation
import SGSimpleSettings

// MARK: DarkGram
//
// Detection for names that do not read the way they render.
//
// Two separate tricks are covered:
//
//   1. Bidirectional overrides. U+202E and friends tell the renderer to lay out the following
//      text right to left. The character itself is invisible and survives copy and paste, so
//      a file named "счёт<U+202E>fdp.exe" is displayed as "счётexe.pdf". The name the user
//      reads and the extension the system acts on are different strings.
//
//   2. Homoglyphs. Cyrillic "с" and Latin "c" are separate characters that render
//      identically, so "Ассount" and "Account" cannot be told apart by eye. This is what
//      fake support channels and impersonated bots are built from.
//
// Nothing here blocks anything. The point is to make the rendered name equal the real name and
// to say when it was not, which is the whole of the defence: both tricks only work while the
// two disagree.

/// Invisible characters that reorder the text around them.
private let darkGramReorderingScalars: Set<UInt32> = [
    0x202A, // LEFT-TO-RIGHT EMBEDDING
    0x202B, // RIGHT-TO-LEFT EMBEDDING
    0x202C, // POP DIRECTIONAL FORMATTING
    0x202D, // LEFT-TO-RIGHT OVERRIDE
    0x202E, // RIGHT-TO-LEFT OVERRIDE
    0x2066, // LEFT-TO-RIGHT ISOLATE
    0x2067, // RIGHT-TO-LEFT ISOLATE
    0x2068, // FIRST STRONG ISOLATE
    0x2069  // POP DIRECTIONAL ISOLATE
]

/// Characters that occupy no space, used to break a string up so it evades matching while
/// still reading normally.
private let darkGramInvisibleScalars: Set<UInt32> = [
    0x200B, // ZERO WIDTH SPACE
    0x200C, // ZERO WIDTH NON-JOINER
    0x200D, // ZERO WIDTH JOINER
    0x2060, // WORD JOINER
    0xFEFF  // ZERO WIDTH NO-BREAK SPACE
]

private enum DarkGramScript: Int {
    case latin = 0
    case cyrillic = 1
    case greek = 2
}

private func darkGramScript(of scalar: UnicodeScalar) -> DarkGramScript? {
    switch scalar.value {
    case 0x0041 ... 0x005A, 0x0061 ... 0x007A:
        return .latin
    case 0x0400 ... 0x052F:
        return .cyrillic
    case 0x0370 ... 0x03FF:
        return .greek
    default:
        // Everything else -- digits, punctuation, emoji, CJK, Arabic -- carries no homoglyph
        // risk against Latin, so it neither counts as a script nor splits a word.
        return nil
    }
}

public struct DarkGramNameInspection {
    /// The name contains characters that change the order the rest is drawn in.
    public let reordersText: Bool
    /// The name contains characters that take up no space.
    public let hidesCharacters: Bool
    /// A single word mixes alphabets whose letters look alike.
    public let mixesScripts: Bool

    public var isSuspicious: Bool {
        return self.reordersText || self.hidesCharacters || self.mixesScripts
    }
}

/// Reports what is wrong with a name, without changing it.
public func darkGramInspectName(_ name: String) -> DarkGramNameInspection {
    var reordersText = false
    var hidesCharacters = false
    var mixesScripts = false

    var scriptsInWord = Set<Int>()
    var sawLetter = false

    func closeWord() {
        if scriptsInWord.count > 1 {
            mixesScripts = true
        }
        scriptsInWord.removeAll()
        sawLetter = false
    }

    for scalar in name.unicodeScalars {
        if darkGramReorderingScalars.contains(scalar.value) {
            reordersText = true
            continue
        }
        if darkGramInvisibleScalars.contains(scalar.value) {
            hidesCharacters = true
            continue
        }
        if let script = darkGramScript(of: scalar) {
            sawLetter = true
            scriptsInWord.insert(script.rawValue)
        } else if scalar.properties.isWhitespace {
            // Only whitespace ends a word. Mixing alphabets across a dot or a hyphen is just as
            // deliberate as mixing them mid-word, and splitting there would hide exactly the
            // file names this is meant to catch.
            closeWord()
        }
    }
    if sawLetter {
        closeWord()
    }

    return DarkGramNameInspection(
        reordersText: reordersText,
        hidesCharacters: hidesCharacters,
        mixesScripts: mixesScripts
    )
}

/// The name with every reordering and invisible character removed, so that what is drawn is
/// what the system will actually act on.
public func darkGramSanitizedName(_ name: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in name.unicodeScalars {
        if darkGramReorderingScalars.contains(scalar.value) || darkGramInvisibleScalars.contains(scalar.value) {
            continue
        }
        result.append(scalar)
    }
    return String(result)
}

// MARK: DarkGram
//
// Query parameters that exist to identify the person following the link rather than to select
// what is shown. They survive being pasted and forwarded, so a link shared in a chat can carry
// the identity of whoever first received it to everyone who opens it afterwards.
//
// Only exact, well-known names are removed, and only from http(s) URLs. A guess here silently
// breaks links, which is worse than the tracking.
private let darkGramTrackingParameters: Set<String> = [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid",
    "yclid", "twclid", "ttclid", "igshid", "mc_eid", "mc_cid",
    "_openstat", "vero_id", "wickedid", "oly_enc_id", "oly_anon_id",
    "ref_src", "ref_url"
]

private func darkGramIsTrackingParameter(_ name: String) -> Bool {
    let lowered = name.lowercased()
    // Every utm_* is analytics by construction, so match the prefix rather than listing them.
    return lowered.hasPrefix("utm_") || darkGramTrackingParameters.contains(lowered)
}

public func darkGramStripTrackingParameters(_ url: String) -> String {
    guard SGSimpleSettings.shared.stripLinkTracking else {
        return url
    }
    guard var components = URLComponents(string: url) else {
        return url
    }
    let scheme = components.scheme?.lowercased()
    guard scheme == "http" || scheme == "https" else {
        return url
    }
    guard let items = components.queryItems, !items.isEmpty else {
        return url
    }
    let kept = items.filter { !darkGramIsTrackingParameter($0.name) }
    guard kept.count != items.count else {
        return url
    }
    components.queryItems = kept.isEmpty ? nil : kept
    return components.string ?? url
}

// MARK: DarkGram
//
// File kinds that do something other than open when opened.
//
// The one that matters most on iOS is .mobileconfig: a configuration profile can install a root
// certificate and a proxy, which turns every HTTPS connection on the device into something the
// issuer can read. It arrives looking like a document.
//
// The rest matter because this is a cross-platform messenger. A file received here is routinely
// opened on a desktop later, where an executable is an executable.
private let darkGramDangerousExtensions: [String: String] = [
    "mobileconfig": "Profile",
    "shortcut": "Shortcut",
    "wfshortcut": "Shortcut",
    "exe": "Executable", "msi": "Executable", "scr": "Executable", "com": "Executable",
    "pif": "Executable", "apk": "Executable", "dmg": "Executable", "pkg": "Executable",
    "bat": "Script", "cmd": "Script", "vbs": "Script", "ps1": "Script",
    "jar": "Script", "sh": "Script"
]

/// A key naming why this file is worth a second look, or nil when it is an ordinary document.
public func darkGramDangerousFileKind(_ fileName: String?) -> String? {
    guard SGSimpleSettings.shared.warnSuspiciousNames, let fileName = fileName else {
        return nil
    }
    // Judge the real name: an override could otherwise hide the extension being checked.
    let sanitized = darkGramSanitizedName(fileName)
    guard let dot = sanitized.lastIndex(of: ".") else {
        return nil
    }
    let ext = String(sanitized[sanitized.index(after: dot)...]).lowercased()
    return darkGramDangerousExtensions[ext]
}

// MARK: DarkGram
//
// Links whose address does not say where they go.
//
// The tracking filter above cleans a link; this reads it. Each case below is a way of making
// the part of an address a person glances at differ from the part a browser acts on:
//
//   - "https://sberbank.ru@evil.example/" -- everything before the @ is a login name the
//     browser discards. The host is evil.example.
//   - "xn--80ak6aa92e.com" -- punycode, the ASCII spelling of a non-Latin domain. It is how a
//     look-alike domain appears when it is copied rather than rendered.
//   - "аpple.com" with a Cyrillic "а" -- one label mixing alphabets that look identical.
//   - a bare IP address -- no name to recognise at all, which ordinary sites never need.
//
// The host is taken apart by hand rather than with URLComponents, whose handling of
// non-ASCII hosts and user-info has changed between iOS releases. A check that silently stops
// seeing the host after an OS update is worse than none.

public enum DarkGramLinkWarning: String {
    case blockedDomain
    case userInfo
    case punycode
    case mixedScripts
    case ipAddress
}

public struct DarkGramLinkInspection {
    public let host: String
    public let warnings: [DarkGramLinkWarning]

    public var isBlocked: Bool {
        return self.warnings.contains(.blockedDomain)
    }
}

/// The authority and whether it carried user-info, for http(s) and scheme-less links only.
private func darkGramLinkAuthority(_ url: String) -> (host: String, hadUserInfo: Bool)? {
    var rest = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if let schemeRange = rest.range(of: "://") {
        let scheme = rest[..<schemeRange.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else {
            return nil
        }
        rest = String(rest[schemeRange.upperBound...])
    } else if rest.contains(":") && !rest.contains(".") {
        // mailto:, tel: and similar carry no host to judge.
        return nil
    }
    if let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
        rest = String(rest[..<end])
    }
    var hadUserInfo = false
    if let at = rest.lastIndex(of: "@") {
        hadUserInfo = true
        rest = String(rest[rest.index(after: at)...])
    }
    if rest.hasPrefix("[") {
        // IPv6 literal; the brackets are the whole host.
        if let close = rest.firstIndex(of: "]") {
            return (String(rest[...close]).lowercased(), hadUserInfo)
        }
        return (rest.lowercased(), hadUserInfo)
    }
    if let colon = rest.lastIndex(of: ":") {
        let port = rest[rest.index(after: colon)...]
        if !port.isEmpty && port.allSatisfy({ $0.isASCII && $0.isNumber }) {
            rest = String(rest[..<colon])
        }
    }
    let host = rest.lowercased()
    if host.isEmpty {
        return nil
    }
    return (host, hadUserInfo)
}

private func darkGramIsIPv4(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else {
        return false
    }
    return parts.allSatisfy { part in
        return !part.isEmpty && part.count <= 3 && part.allSatisfy({ $0.isASCII && $0.isNumber })
    }
}

/// The user's blocklist, normalised. A leading "*." or a pasted scheme is tolerated, since
/// that is how people copy domains around.
public func darkGramBlockedDomains() -> [String] {
    let separators = CharacterSet(charactersIn: ", ;").union(.whitespacesAndNewlines)
    return SGSimpleSettings.shared.blockedDomains
        .components(separatedBy: separators)
        .compactMap { raw -> String? in
            var domain = raw.lowercased()
            if let schemeRange = domain.range(of: "://") {
                domain = String(domain[schemeRange.upperBound...])
            }
            if domain.hasPrefix("*.") {
                domain = String(domain.dropFirst(2))
            }
            while domain.hasSuffix("/") || domain.hasSuffix(".") {
                domain = String(domain.dropLast())
            }
            return domain.isEmpty ? nil : domain
        }
}

public func darkGramInspectLink(_ url: String) -> DarkGramLinkInspection? {
    guard let authority = darkGramLinkAuthority(url) else {
        return nil
    }
    let host = authority.host
    var warnings: [DarkGramLinkWarning] = []

    // The blocklist is the user's own decision, so it applies whether or not the address
    // checks are switched on.
    for domain in darkGramBlockedDomains() {
        if host == domain || host.hasSuffix("." + domain) {
            warnings.append(.blockedDomain)
            break
        }
    }

    if SGSimpleSettings.shared.checkLinkAddress {
        if authority.hadUserInfo {
            warnings.append(.userInfo)
        }
        if host.hasPrefix("[") || darkGramIsIPv4(host) {
            warnings.append(.ipAddress)
        } else {
            let labels = host.split(separator: ".")
            if labels.contains(where: { $0.hasPrefix("xn--") }) {
                warnings.append(.punycode)
            }
            let mixes = labels.contains { label in
                var scripts = Set<Int>()
                for scalar in label.unicodeScalars {
                    if let script = darkGramScript(of: scalar) {
                        scripts.insert(script.rawValue)
                    }
                }
                return scripts.count > 1
            }
            if mixes {
                warnings.append(.mixedScripts)
            }
        }
    }

    return DarkGramLinkInspection(host: host, warnings: warnings)
}

// MARK: DarkGram
//
// Accounts that present themselves as a service.
//
// "Telegram Support", "Служба безопасности", "@premium_notify": nobody official writes to you
// from an unverified account, and every account that claims to is running the same script --
// ask for the login code, or for a payment, before something is "blocked". Telegram marks
// verified accounts and the scam ones it has already caught; this covers the gap in between,
// an unverified name that claims authority.
//
// Latin terms are also matched after folding Cyrillic look-alikes, so "Tеlеgram" with Cyrillic
// "е" does not slip past the very check meant for it.

private let darkGramServiceTermsLatin: [String] = [
    // Kept to words that claim authority. "admin" or "premium" alone would flag every
    // badminton club and every shop, and a warning that is usually wrong stops being read.
    "telegram", "support", "security", "official", "administrator", "moderator",
    "notification", "verify", "verification"
]

private let darkGramServiceTermsCyrillic: [String] = [
    "телеграм", "поддержк", "безопасност", "официальн", "администрац",
    "модератор", "служба", "уведомлен", "верификац"
]

private let darkGramLatinLookalikes: [Character: Character] = [
    "а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h", "о": "o",
    "р": "p", "с": "c", "т": "t", "у": "y", "х": "x", "і": "i", "ѕ": "s"
]

public func darkGramImitatesService(name: String, username: String) -> Bool {
    let text = (darkGramSanitizedName(name) + " " + username).lowercased()
    for term in darkGramServiceTermsCyrillic where text.contains(term) {
        return true
    }
    let folded = String(text.map({ darkGramLatinLookalikes[$0] ?? $0 }))
    for term in darkGramServiceTermsLatin where folded.contains(term) {
        return true
    }
    return false
}
