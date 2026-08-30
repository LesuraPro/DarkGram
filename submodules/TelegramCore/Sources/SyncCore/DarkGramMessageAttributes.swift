import Foundation
import Postbox

/// MARK: DarkGram
/// Marks a message the server asked to delete but that was kept in the local
/// database instead. The message is never removed, so its media and position in
/// the history stay intact; only this marker distinguishes it.
public class DarkGramDeletedMessageAttribute: MessageAttribute {
    /// Unix time at which the deletion arrived from the server.
    public let deletedAt: Int32

    public init(deletedAt: Int32) {
        self.deletedAt = deletedAt
    }

    required public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "d")
    }
}

/// MARK: DarkGram
/// Previous texts of an edited message, oldest first. `texts` and `timestamps`
/// are parallel arrays — index i holds the text that was replaced at time i.
/// Kept as two primitive arrays rather than an array of objects so the attribute
/// needs no nested encodable type.
public class DarkGramEditHistoryAttribute: MessageAttribute {
    public let texts: [String]
    public let timestamps: [Int32]

    public init(texts: [String], timestamps: [Int32]) {
        self.texts = texts
        self.timestamps = timestamps
    }

    /// Appends one superseded revision, capped so a message edited in a loop
    /// cannot grow the stored record without bound.
    public func appending(text: String, timestamp: Int32, limit: Int = 32) -> DarkGramEditHistoryAttribute {
        var texts = self.texts
        var timestamps = self.timestamps
        texts.append(text)
        timestamps.append(timestamp)
        if texts.count > limit {
            texts.removeFirst(texts.count - limit)
            timestamps.removeFirst(timestamps.count - limit)
        }
        return DarkGramEditHistoryAttribute(texts: texts, timestamps: timestamps)
    }

    required public init(decoder: PostboxDecoder) {
        let texts = decoder.decodeStringArrayForKey("t")
        let timestamps = decoder.decodeInt32ArrayForKey("s")
        // Defensive: a truncated or partially written record must not produce
        // mismatched arrays that later index out of range.
        let count = min(texts.count, timestamps.count)
        self.texts = Array(texts.prefix(count))
        self.timestamps = Array(timestamps.prefix(count))
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeStringArray(self.texts, forKey: "t")
        encoder.encodeInt32Array(self.timestamps, forKey: "s")
    }
}

public extension Message {
    /// Non-nil when this message was deleted on the server but kept locally.
    var darkGramDeletedAttribute: DarkGramDeletedMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? DarkGramDeletedMessageAttribute {
                return attribute
            }
        }
        return nil
    }

    /// Non-nil when earlier revisions of this message's text were recorded.
    var darkGramEditHistoryAttribute: DarkGramEditHistoryAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? DarkGramEditHistoryAttribute {
                return attribute
            }
        }
        return nil
    }
}
