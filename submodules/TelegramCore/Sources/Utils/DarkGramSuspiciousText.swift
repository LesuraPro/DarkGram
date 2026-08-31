import Foundation

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
