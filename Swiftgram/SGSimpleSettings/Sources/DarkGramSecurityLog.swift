import Foundation

// MARK: DarkGram
//
// One place that answers "did anything happen?".
//
// Each protection already speaks up at the moment it fires -- a new session, a renamed contact,
// a link that was stopped. But an alert is gone once dismissed, and the question usually comes
// later: was there anything odd this week? This keeps a short record of every such moment.
//
// It lives here rather than in TelegramCore because both the core (session and rename
// detection) and the interface (links, sending) write to it, and this module is the one both
// already depend on. Stored on this device only; nothing here is sent anywhere.

public struct DarkGramSecurityEvent {
    public let timestamp: Int32
    public let kind: String
    public let detail: String
}

public final class DarkGramSecurityLog {
    public static let shared = DarkGramSecurityLog()

    /// Enough to cover weeks of ordinary use without the stored string growing without bound.
    private let limit = 200
    private let lock = NSLock()

    private init() {
    }

    /// Kinds are stable keys, localised only when shown, so an old entry still reads correctly
    /// after the language is changed.
    public func append(kind: String, detail: String) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var entries = self.load()
        var entry: [String: Any] = [:]
        entry["t"] = Int(Date().timeIntervalSince1970)
        entry["k"] = kind
        entry["d"] = detail
        entries.append(entry)
        if entries.count > self.limit {
            entries.removeFirst(entries.count - self.limit)
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries), let string = String(data: data, encoding: .utf8) {
            SGSimpleSettings.shared.securityLog = string
        }
    }

    /// Newest first, which is the order anyone reading it wants.
    public func events() -> [DarkGramSecurityEvent] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var result: [DarkGramSecurityEvent] = []
        for entry in self.load() {
            guard let kind = entry["k"] as? String else {
                continue
            }
            let timestamp = (entry["t"] as? NSNumber)?.int32Value ?? 0
            let detail = (entry["d"] as? String) ?? ""
            result.append(DarkGramSecurityEvent(timestamp: timestamp, kind: kind, detail: detail))
        }
        return result.reversed()
    }

    public func clear() {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        SGSimpleSettings.shared.securityLog = ""
    }

    private func load() -> [[String: Any]] {
        let stored = SGSimpleSettings.shared.securityLog
        guard !stored.isEmpty, let data = stored.data(using: .utf8) else {
            return []
        }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []
    }
}
