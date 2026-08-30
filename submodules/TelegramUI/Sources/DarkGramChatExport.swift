import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
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
    </style></head><body>
    <h1>\(darkGramEscapeHTML(chatTitle))</h1>
    <div class="meta">\(messages.count) messages · exported \(formatter.string(from: Date())) · DarkGram</div>

    """

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
        html += "<span class=\"when\">\(timestamp)</span>"
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

        controllerInteraction.presentController(textAlertController(
            context: context,
            title: EnginePeer(peer).compactDisplayTitle,
            text: lines.joined(separator: "\n"),
            actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]
        ), nil)
    })
}
