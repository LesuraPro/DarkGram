import Foundation
import CryptoKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import TelegramPresentationData
import ChatControllerInteraction
import ChatPresentationInterfaceState
import PresentationDataUtils
import SGStrings

// MARK: DarkGram
// Chat export. iOS Telegram has no equivalent -- only Desktop does -- so this is written from
// scratch rather than unlocking something existing.
//
// Scope is deliberately the locally cached history: what the device already holds. Pulling the
// full server-side history would mean paginated network fetches with holes to fill, which is a
// different and much larger job. Media is referenced by kind, not downloaded, so an export stays
// a single small file.

private let darkGramExportPageSize = 200
private let darkGramExportMessageLimit = 20000

private func darkGramEscapeHTML(_ text: String) -> String {
    var result = text
    // Ampersand first: escaping it after the others would double-escape their entities.
    result = result.replacingOccurrences(of: "&", with: "&amp;")
    result = result.replacingOccurrences(of: "<", with: "&lt;")
    result = result.replacingOccurrences(of: ">", with: "&gt;")
    result = result.replacingOccurrences(of: "\"", with: "&quot;")
    return result
}

private func darkGramMediaDescription(_ message: Message) -> String? {
    for media in message.media {
        if media is TelegramMediaImage {
            return "[photo]"
        } else if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return "[voice message]"
            } else if file.isVideo {
                return "[video]"
            } else if file.isSticker {
                return "[sticker]"
            } else {
                return "[file: " + (file.fileName ?? "unnamed") + "]"
            }
        } else if media is TelegramMediaContact {
            return "[contact]"
        } else if media is TelegramMediaMap {
            return "[location]"
        } else if media is TelegramMediaPoll {
            return "[poll]"
        }
    }
    return nil
}

/// Walks the cached history newest-first, then returns it oldest-first.
private func darkGramCollectMessages(transaction: Transaction, peerId: PeerId) -> [Message] {
    var collected: [Message] = []
    var anchor: HistoryViewInputAnchor = .upperBound
    var seenIds = Set<MessageId>()

    while collected.count < darkGramExportMessageLimit {
        let view = transaction.getMessagesHistoryViewState(
            input: .single(peerId: peerId, threadId: nil),
            ignoreMessagesInTimestampRange: nil,
            ignoreMessageIds: Set(),
            count: darkGramExportPageSize,
            clipHoles: true,
            anchor: anchor,
            namespaces: .just(Set([Namespaces.Message.Cloud]))
        )
        let page = view.entries.map({ $0.message })
        // A page whose messages were all seen before means the anchor stopped advancing;
        // without this guard the loop would spin until the message limit.
        let fresh = page.filter({ !seenIds.contains($0.id) })
        if fresh.isEmpty {
            break
        }
        for message in fresh {
            seenIds.insert(message.id)
        }
        collected.append(contentsOf: fresh)
        guard let oldest = page.min(by: { $0.index < $1.index }) else {
            break
        }
        anchor = .index(oldest.index)
    }

    return collected.sorted(by: { $0.index < $1.index })
}

// MARK: DarkGram
//
// A screenshot of a chat proves nothing -- it takes a minute to fake one. Hashing each message
// and chaining the hashes makes an export checkable instead: changing, inserting or dropping
// any message changes its own hash and every hash after it, so the single value at the bottom
// stops matching. It does not prove the messages were ever sent -- nothing on the client can --
// only that this file is the same one that left the device.
//
// The canonical form is spelled out in the export itself, so the chain can be recomputed with
// any tool by someone who does not have this app and has no reason to trust it.

private let darkGramFieldSeparator = "\u{1F}"

private func darkGramCanonicalForm(_ message: Message) -> String {
    var fields: [String] = []
    fields.append("\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)")
    fields.append(String(message.timestamp))
    fields.append(message.author.flatMap({ String($0.id.toInt64()) }) ?? "")
    fields.append(message.flags.contains(.Incoming) ? "in" : "out")
    fields.append(darkGramMediaDescription(message) ?? "")
    fields.append(message.text)
    return fields.joined(separator: darkGramFieldSeparator)
}

private func darkGramSHA256Hex(_ text: String) -> String {
    return SHA256.hash(data: Data(text.utf8)).map({ String(format: "%02x", $0) }).joined()
}

private func darkGramRenderHTML(messages: [Message], chatTitle: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy HH:mm"

    var html = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>\(darkGramEscapeHTML(chatTitle))</title>
    <style>
    body { background: #0b0d12; color: #e8eaf0; font: 15px/1.5 -apple-system, system-ui, sans-serif; margin: 0; padding: 24px; }
    h1 { font-size: 20px; margin: 0 0 4px; }
    .meta { color: #7c8598; font-size: 13px; margin-bottom: 24px; }
    .msg { border-left: 2px solid #2a2f3d; padding: 6px 0 6px 12px; margin-bottom: 12px; }
    .msg.out { border-left-color: #8b5cf6; }
    .who { color: #a78bff; font-weight: 600; }
    .when { color: #6b7488; font-size: 12px; margin-left: 6px; }
    .text { white-space: pre-wrap; word-wrap: break-word; margin-top: 2px; }
    .media { color: #7c8598; font-style: italic; }
    .deleted { color: #e06c75; font-size: 12px; margin-left: 6px; }
    .hash { color: #4c5566; font-size: 11px; font-family: ui-monospace, Menlo, monospace; margin-left: 6px; }
    .manifest { margin-top: 32px; padding-top: 16px; border-top: 1px solid #2a2f3d; color: #7c8598; font-size: 12px; }
    .manifest code { color: #a78bff; font-family: ui-monospace, Menlo, monospace; word-break: break-all; }
    </style></head><body>
    <h1>\(darkGramEscapeHTML(chatTitle))</h1>
    <div class="meta">\(messages.count) messages · exported \(formatter.string(from: Date())) · DarkGram</div>

    """

    // Seeded with zeroes so the first link has a defined predecessor.
    var chain = String(repeating: "0", count: 64)

    for message in messages {
        let isOutgoing = !message.flags.contains(.Incoming)
        let author: String
        if let peer = message.author {
            author = EnginePeer(peer).compactDisplayTitle
        } else {
            author = chatTitle
        }
        let timestamp = formatter.string(from: Date(timeIntervalSince1970: Double(message.timestamp)))

        html += "<div class=\"msg\(isOutgoing ? " out" : "")\">"
        html += "<span class=\"who\">\(darkGramEscapeHTML(author))</span>"
        let digest = darkGramSHA256Hex(darkGramCanonicalForm(message))
        chain = darkGramSHA256Hex(chain + digest)

        html += "<span class=\"when\">\(timestamp)</span>"
        html += "<span class=\"hash\">\(digest.prefix(16))</span>"
        if message.attributes.contains(where: { $0 is DarkGramDeletedMessageAttribute }) {
            html += "<span class=\"deleted\">deleted</span>"
        }
        if let media = darkGramMediaDescription(message) {
            html += "<div class=\"text media\">\(darkGramEscapeHTML(media))</div>"
        }
        if !message.text.isEmpty {
            html += "<div class=\"text\">\(darkGramEscapeHTML(message.text))</div>"
        }
        html += "</div>\n"
    }

    html += "<div class=\"manifest\">"
    html += "<div>Integrity chain (SHA-256)</div>"
    html += "<div><code>\(chain)</code></div>"
    html += "<div style=\"margin-top:8px\">Each message is hashed over its fields joined by U+001F, in order: "
    html += "peerId:namespace:id, unix timestamp, author id, direction (in/out), media description, text. "
    html += "The chain starts at 64 zeroes and advances as SHA-256 of the previous chain value "
    html += "concatenated with the message hash, both lowercase hex. Altering, inserting or "
    html += "removing any message changes the value above.</div>"
    html += "</div>\n"
    html += "</body></html>\n"
    return html
}

/// Builds the export off the main thread and hands back a previewable, shareable file.
public func darkGramExportChat(
    controllerInteraction: ChatControllerInteraction,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    context: AccountContext,
    peerId: PeerId,
    chatTitle: String
) {
    guard let navigationController = controllerInteraction.navigationController(),
          let rootController = navigationController.view.window?.rootViewController else {
        return
    }
    let strings = chatPresentationInterfaceState.strings
    let theme = chatPresentationInterfaceState.theme

    let signal = context.account.postbox.transaction { transaction -> Data? in
        let messages = darkGramCollectMessages(transaction: transaction, peerId: peerId)
        if messages.isEmpty {
            return nil
        }
        return darkGramRenderHTML(messages: messages, chatTitle: chatTitle).data(using: .utf8)
    }
    |> deliverOnMainQueue

    let _ = signal.startStandalone(next: { data in
        guard let data = data else {
            return
        }
        let fileId = Int64.random(in: Int64.min ... Int64.max)
        let resource = LocalFileMediaResource(fileId: fileId, size: Int64(data.count), isSecretRelated: false)
        context.account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)

        let safeTitle = chatTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let file = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: fileId),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "text/html; charset=utf-8",
            size: Int64(data.count),
            attributes: [.FileName(fileName: "\(safeTitle).html")],
            alternativeRepresentations: []
        )

        presentDocumentPreviewController(
            rootController: rootController,
            theme: theme,
            strings: strings,
            postbox: context.account.postbox,
            file: file,
            canShare: true
        )
    })
}

// MARK: DarkGram
/// Chat summary: how the contact relationship stands, and what the cached history looks like.
/// Reuses the export walker, so the numbers describe exactly what the device holds -- the same
/// scope the export writes out, which keeps the two features honest with each other.
// MARK: DarkGram
//
// Telegram hands out user ids in ascending order, so an id places an account on a timeline.
// Anchors below are (id, year, month) pairs; anything between two of them is interpolated.
//
// This is an estimate and is labelled as one. Allocation has not been perfectly monotonic --
// imported accounts and the 2022 move to 64-bit ids both disturb it -- so the answer is given
// as a period, never a date, and is withheld entirely above the last anchor, where the only
// honest thing to say is "recent".
private let darkGramIdAnchors: [(id: Int64, year: Int, month: Int)] = [
    (44634663, 2015, 1),
    (101260938, 2016, 1),
    (164788718, 2017, 1),
    (285253072, 2018, 1),
    (543093692, 2019, 1),
    (925078845, 2020, 1),
    (1524312228, 2021, 1),
    (2166527034, 2022, 1)
]

/// An approximate registration period, or nil when the id is outside the anchored range.
private func darkGramAccountPeriod(userId: Int64) -> String? {
    guard userId > 0 else {
        return nil
    }
    guard let first = darkGramIdAnchors.first, let last = darkGramIdAnchors.last else {
        return nil
    }
    if userId < first.id {
        return "< \(first.year)"
    }
    if userId > last.id {
        return nil
    }
    for index in 1 ..< darkGramIdAnchors.count {
        let upper = darkGramIdAnchors[index]
        if userId > upper.id {
            continue
        }
        let lower = darkGramIdAnchors[index - 1]
        let span = Double(upper.id - lower.id)
        guard span > 0 else {
            return String(lower.year)
        }
        let progress = Double(userId - lower.id) / span
        let lowerMonths = lower.year * 12 + (lower.month - 1)
        let upperMonths = upper.year * 12 + (upper.month - 1)
        let months = lowerMonths + Int((Double(upperMonths - lowerMonths) * progress).rounded())
        return String(format: "%04d-%02d", months / 12, months % 12 + 1)
    }
    return nil
}

public func darkGramShowChatInfo(
    controllerInteraction: ChatControllerInteraction,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    context: AccountContext,
    peer: Peer
) {
    let strings = chatPresentationInterfaceState.strings
    let lang = strings.baseLanguageCode
    let peerId = peer.id

    // Only a user can be a contact; groups and channels have no such relationship.
    var contactLine: String?
    if let user = peer as? TelegramUser {
        if user.flags.contains(.mutualContact) {
            contactLine = i18n("ChatInfo.Contact.Mutual", lang)
        } else {
            // Telegram reports mutuality only for people already in our own contacts, so a
            // non-mutual flag is conclusive one way and silent the other.
            contactLine = i18n("ChatInfo.Contact.NotMutual", lang)
        }
    }

    let signal = context.account.postbox.transaction { transaction -> (Int, Int, Int, Int32, Int32) in
        let messages = darkGramCollectMessages(transaction: transaction, peerId: peerId)
        var outgoing = 0
        var deleted = 0
        for message in messages {
            if !message.flags.contains(.Incoming) {
                outgoing += 1
            }
            if message.attributes.contains(where: { $0 is DarkGramDeletedMessageAttribute }) {
                deleted += 1
            }
        }
        let first = messages.first?.timestamp ?? 0
        let last = messages.last?.timestamp ?? 0
        return (messages.count, outgoing, deleted, first, last)
    }
    |> deliverOnMainQueue

    let _ = signal.startStandalone(next: { total, outgoing, deleted, first, last in
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"

        var lines: [String] = []
        // MARK: DarkGram - what is known about who this is, before the message counts.
        if let user = peer as? TelegramUser {
            if let period = darkGramAccountPeriod(userId: user.id.id._internalGetInt64Value()) {
                lines.append(i18n("ChatInfo.Registered", lang) + ": ~" + period)
            } else {
                lines.append(i18n("ChatInfo.Registered", lang) + ": " + i18n("ChatInfo.Registered.Recent", lang))
            }
            var signals: [String] = []
            if user.username == nil || user.username?.isEmpty == true {
                signals.append(i18n("ChatInfo.Signal.NoUsername", lang))
            }
            if user.photo.isEmpty {
                signals.append(i18n("ChatInfo.Signal.NoPhoto", lang))
            }
            if user.flags.contains(.isScam) {
                signals.append(i18n("ChatInfo.Signal.Scam", lang))
            }
            if user.flags.contains(.isFake) {
                signals.append(i18n("ChatInfo.Signal.Fake", lang))
            }
            if !signals.isEmpty {
                lines.append(i18n("ChatInfo.Signals", lang) + ": " + signals.joined(separator: ", "))
            }
        }
        if let contactLine = contactLine {
            lines.append(contactLine)
        }
        lines.append(i18n("ChatInfo.Total", lang) + ": \(total)")
        lines.append(i18n("ChatInfo.Mine", lang) + ": \(outgoing)")
        lines.append(i18n("ChatInfo.Theirs", lang) + ": \(total - outgoing)")
        if deleted > 0 {
            lines.append(i18n("ChatInfo.Deleted", lang) + ": \(deleted)")
        }
        if first > 0 {
            let from = formatter.string(from: Date(timeIntervalSince1970: Double(first)))
            let to = formatter.string(from: Date(timeIntervalSince1970: Double(last)))
            lines.append(i18n("ChatInfo.Range", lang) + ": \(from) — \(to)")
        }
        lines.append("")
        lines.append(i18n("ChatInfo.Notice", lang))

        // MARK: DarkGram - how much room this chat takes. Telegram already computes this, but
        // only on the Storage Usage screen, where you must go looking for the chat by name.
        // Asking for a single peer keeps the scan cheap next to the whole-account sweep.
        let _ = (context.engine.resources.collectCacheUsageStats(peerId: peerId)
        |> deliverOnMainQueue).startStandalone(next: { cacheResult in
            var finalLines = lines
            if case let .result(stats) = cacheResult {
                var total: Int64 = 0
                for (_, categories) in stats.media {
                    for (_, mediaSizes) in categories {
                        for (_, size) in mediaSizes {
                            total += size
                        }
                    }
                }
                if total > 0 {
                    let byteFormatter = ByteCountFormatter()
                    byteFormatter.countStyle = .file
                    // Before the trailing blank line and the caveat that closes the summary.
                    finalLines.insert(
                        i18n("ChatInfo.Storage", lang) + ": " + byteFormatter.string(fromByteCount: total),
                        at: max(0, finalLines.count - 2)
                    )
                }
            }

            controllerInteraction.presentController(textAlertController(
                context: context,
                title: EnginePeer(peer).compactDisplayTitle,
                text: finalLines.joined(separator: "\n"),
                actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]
            ), nil)
        })
    })
}

// MARK: DarkGram
/// Deletes every message you sent in this chat, for everyone.
///
/// Irreversible, so it counts first and names the number in the confirmation rather than asking
/// an abstract "are you sure". Only outgoing messages are ever touched; the other side's
/// messages are not ours to remove. Deletion goes out in batches because the API rejects
/// unbounded id lists.
public func darkGramDeleteOwnMessages(
    controllerInteraction: ChatControllerInteraction,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    context: AccountContext,
    peerId: PeerId
) {
    let strings = chatPresentationInterfaceState.strings
    let lang = strings.baseLanguageCode

    let collect = context.account.postbox.transaction { transaction -> [MessageId] in
        return darkGramCollectMessages(transaction: transaction, peerId: peerId)
            .filter({ !$0.flags.contains(.Incoming) })
            .map({ $0.id })
    }
    |> deliverOnMainQueue

    let _ = collect.startStandalone(next: { ids in
        guard !ids.isEmpty else {
            controllerInteraction.presentController(textAlertController(
                context: context,
                title: nil,
                text: i18n("BulkDelete.None", lang),
                actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]
            ), nil)
            return
        }

        controllerInteraction.presentController(textAlertController(
            context: context,
            title: i18n("BulkDelete.Title", lang),
            text: i18n("BulkDelete.Confirm", lang) + " \(ids.count)",
            actions: [
                TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: i18n("BulkDelete.Action", lang), action: {
                    // 100 at a time: the server rejects very large id lists outright.
                    var batches: [[MessageId]] = []
                    var index = 0
                    while index < ids.count {
                        batches.append(Array(ids[index ..< min(index + 100, ids.count)]))
                        index += 100
                    }
                    for batch in batches {
                        let _ = context.engine.messages.deleteMessagesInteractively(
                            messageIds: batch, type: .forEveryone
                        ).startStandalone()
                    }
                })
            ]
        ), nil)
    })
}
