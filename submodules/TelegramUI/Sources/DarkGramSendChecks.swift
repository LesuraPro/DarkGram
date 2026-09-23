import Foundation
import ImageIO
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import SGSimpleSettings
import SGStrings

// MARK: DarkGram
//
// Two things that should never leave the device by accident.
//
// The login code. Taking over a Telegram account does not need a vulnerability: it needs the
// owner to send the five digits Telegram just texted them to whoever asked -- "support", a
// "friend" whose account was taken the same way, a giveaway bot. Telegram itself voids a code
// that is sent as-is, so the scripts now ask for it with spaces or dashes in between. This
// compares the digits of the outgoing text against the code actually received, so spacing does
// not hide it and an ordinary number does not trigger it.
//
// Location in a photo. A picture sent as a file is sent byte for byte, and a phone photo
// carries the coordinates where it was taken. Compressed photos are re-encoded by Telegram and
// lose them, which is exactly why people forget the file path keeps them.
//
// The expensive part -- a database read, opening a file -- only runs when a message could
// possibly be affected. Everything else is decided synchronously from what is already in
// memory, so ordinary sending is not delayed at all.

private let darkGramServiceNotificationsId: Int64 = 777000
/// Codes are short-lived; anything older than this is not worth interrupting a send for.
private let darkGramLoginCodeWindow: Int32 = 24 * 60 * 60

private func darkGramDigits(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where scalar.value >= 0x30 && scalar.value <= 0x39 {
        result.append(scalar)
    }
    return String(result)
}

/// The first standalone run of five or six digits: the shape of a login code.
private func darkGramExtractLoginCode(_ text: String) -> String? {
    var runs: [String] = []
    var run = ""
    for character in text {
        if character.isASCII && character.isNumber {
            run.append(character)
        } else {
            runs.append(run)
            run = ""
        }
    }
    runs.append(run)
    return runs.first(where: { $0.count == 5 || $0.count == 6 })
}

private func darkGramOutgoingTexts(_ messages: [EnqueueMessage]) -> [String] {
    var result: [String] = []
    for message in messages {
        if case let .message(text, _, _, _, _, _, _, _, _, _) = message, !text.isEmpty {
            result.append(text)
        }
    }
    return result
}

private func darkGramOutgoingFiles(_ messages: [EnqueueMessage]) -> [TelegramMediaFile] {
    var result: [TelegramMediaFile] = []
    for message in messages {
        if case let .message(_, _, _, mediaReference, _, _, _, _, _, _) = message, let file = mediaReference?.media as? TelegramMediaFile {
            result.append(file)
        }
    }
    return result
}

private func darkGramCouldCarryLocation(_ file: TelegramMediaFile) -> Bool {
    if file.mimeType.hasPrefix("image/") {
        return true
    }
    let name = (file.fileName ?? "").lowercased()
    for suffix in [".jpg", ".jpeg", ".heic", ".heif", ".png", ".tif", ".tiff", ".dng"] {
        if name.hasSuffix(suffix) {
            return true
        }
    }
    return false
}

/// Cheap and synchronous: whether any of the checks below could possibly find something.
func darkGramSendNeedsCheck(_ messages: [EnqueueMessage]) -> Bool {
    if SGSimpleSettings.shared.guardLoginCode {
        for text in darkGramOutgoingTexts(messages) where darkGramDigits(text).count >= 5 {
            return true
        }
    }
    if SGSimpleSettings.shared.warnFileMetadata {
        if darkGramOutgoingFiles(messages).contains(where: darkGramCouldCarryLocation) {
            return true
        }
    }
    return false
}

private func darkGramLoginCodeWarning(context: AccountContext, peerId: PeerId, messages: [EnqueueMessage], lang: String) -> Signal<[String], NoError> {
    guard SGSimpleSettings.shared.guardLoginCode else {
        return .single([])
    }
    let serviceId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(darkGramServiceNotificationsId))
    if peerId == serviceId {
        return .single([])
    }
    let outgoingDigits = darkGramOutgoingTexts(messages).map(darkGramDigits)
    if !outgoingDigits.contains(where: { $0.count >= 5 }) {
        return .single([])
    }
    return context.account.postbox.transaction { transaction -> [String] in
        guard let index = transaction.getTopPeerMessageIndex(peerId: serviceId, namespace: Namespaces.Message.Cloud),
              let message = transaction.getMessage(index.id),
              message.flags.contains(.Incoming) else {
            return []
        }
        let now = Int32(Date().timeIntervalSince1970)
        guard now - message.timestamp < darkGramLoginCodeWindow,
              let code = darkGramExtractLoginCode(message.text) else {
            return []
        }
        if outgoingDigits.contains(where: { $0.contains(code) }) {
            DarkGramSecurityLog.shared.append(kind: "loginCode", detail: "")
            return [i18n("SendCheck.LoginCode", lang)]
        }
        return []
    }
}

private func darkGramLocationWarning(context: AccountContext, messages: [EnqueueMessage], lang: String) -> Signal<[String], NoError> {
    guard SGSimpleSettings.shared.warnFileMetadata else {
        return .single([])
    }
    let files = darkGramOutgoingFiles(messages).filter(darkGramCouldCarryLocation)
    if files.isEmpty {
        return .single([])
    }
    let mediaBox = context.account.postbox.mediaBox
    return Signal<[String], NoError> { subscriber in
        var names: [String] = []
        for file in files {
            let path: String?
            if let local = file.resource as? LocalFileReferenceMediaResource {
                path = local.localFilePath
            } else {
                path = mediaBox.completedResourcePath(file.resource)
            }
            guard let path = path,
                  let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                continue
            }
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty {
                names.append(file.fileName ?? "")
            }
        }
        if names.isEmpty {
            subscriber.putNext([])
        } else {
            DarkGramSecurityLog.shared.append(kind: "fileLocation", detail: names.joined(separator: ", "))
            subscriber.putNext([i18n("SendCheck.Location", lang) + "\n" + names.filter({ !$0.isEmpty }).joined(separator: "\n")])
        }
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
}

/// Human-readable reasons to confirm before sending; empty when there is nothing to say.
func darkGramSendWarnings(context: AccountContext, peerId: PeerId, messages: [EnqueueMessage], lang: String) -> Signal<[String], NoError> {
    return combineLatest(
        darkGramLoginCodeWarning(context: context, peerId: peerId, messages: messages, lang: lang),
        darkGramLocationWarning(context: context, messages: messages, lang: lang)
    )
    |> map { code, location -> [String] in
        return code + location
    }
}
