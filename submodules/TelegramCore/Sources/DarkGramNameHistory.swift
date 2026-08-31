import Foundation
import Postbox
import SGSimpleSettings

// MARK: DarkGram
//
// Records when a contact or channel changes the name or username it presents.
//
// Telegram applies such a change silently and keeps no history, which is exactly what makes it
// useful to an attacker. A sold or stolen account keeps its id, its message history and its
// place in your chat list while becoming someone else entirely; a channel renames itself into
// the support channel of whatever it wants to impersonate. Either way the only evidence is a
// name you half-remember.
//
// Cost matters here: updatePeersCustom runs inside a Postbox transaction for every peer the
// server sends, in batches of thousands during a sync. So the comparison is done first on
// values already in memory, and the setting is not read at all unless something actually
// changed -- which is rare. Nothing touches UserDefaults on the common path.

private let darkGramNameLogLimit = 100

public struct DarkGramNameChange {
    public let peerId: Int64
    public let timestamp: Int32
    public let previousName: String
    public let currentName: String
    public let previousUsername: String
    public let currentUsername: String
}

private final class DarkGramNameLog {
    static let shared = DarkGramNameLog()

    private let lock = NSLock()

    func append(_ entry: [String: Any]) {
        self.lock.lock()
        defer { self.lock.unlock() }

        var entries = self.loadLocked()
        entries.append(entry)
        if entries.count > darkGramNameLogLimit {
            entries.removeFirst(entries.count - darkGramNameLogLimit)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        SGSimpleSettings.shared.nameChangeLog = text
    }

    func entries(forPeerId peerId: Int64) -> [DarkGramNameChange] {
        self.lock.lock()
        defer { self.lock.unlock() }

        return self.loadLocked().compactMap { raw in
            guard let stored = (raw["p"] as? NSNumber)?.int64Value, stored == peerId else {
                return nil
            }
            return DarkGramNameChange(
                peerId: stored,
                timestamp: (raw["t"] as? NSNumber)?.int32Value ?? 0,
                previousName: raw["n"] as? String ?? "",
                currentName: raw["N"] as? String ?? "",
                previousUsername: raw["u"] as? String ?? "",
                currentUsername: raw["U"] as? String ?? ""
            )
        }
    }

    private func loadLocked() -> [[String: Any]] {
        let stored = SGSimpleSettings.shared.nameChangeLog
        guard !stored.isEmpty, let data = stored.data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return entries
    }
}

private func darkGramPresentedName(_ peer: Peer) -> (name: String, username: String)? {
    if let user = peer as? TelegramUser {
        let name = [user.firstName, user.lastName].compactMap({ $0 }).joined(separator: " ")
        return (name, user.username ?? "")
    }
    if let channel = peer as? TelegramChannel {
        return (channel.title, channel.username ?? "")
    }
    if let group = peer as? TelegramGroup {
        return (group.title, "")
    }
    return nil
}

func darkGramRecordNameChange(previous: Peer?, updated: Peer) {
    guard let previous = previous,
          let before = darkGramPresentedName(previous),
          let after = darkGramPresentedName(updated) else {
        return
    }
    // Cheap comparison of values already in memory; everything below runs only on a real change.
    if before.name == after.name && before.username == after.username {
        return
    }
    // A peer arriving without a name yet is a partial update, not a rename.
    if after.name.isEmpty && after.username.isEmpty {
        return
    }
    guard SGSimpleSettings.shared.trackNameChanges else {
        return
    }
    DarkGramNameLog.shared.append([
        "p": NSNumber(value: updated.id.toInt64()),
        "t": NSNumber(value: Int32(Date().timeIntervalSince1970)),
        "n": before.name,
        "N": after.name,
        "u": before.username,
        "U": after.username
    ])
}

public func darkGramNameChanges(forPeerId peerId: Int64) -> [DarkGramNameChange] {
    return DarkGramNameLog.shared.entries(forPeerId: peerId)
}
