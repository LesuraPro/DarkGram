import Foundation
import UIKit
import CryptoKit
import Display
import TelegramCore
import SwiftSignalKit
import AccountContext
import ChatControllerInteraction
import ChatPresentationInterfaceState
import PresentationDataUtils
import SGStrings

// MARK: DarkGram
//
// The SHA-256 of a received file.
//
// A hash is how a file is checked without opening it: pasted into VirusTotal it says whether
// anyone has seen this exact file before and what they made of it; compared with a hash the
// sender published it says whether the file changed on the way. Both need the hash, and no
// Telegram client shows one.
//
// Only a file already on the device is hashed. Downloading something in order to decide
// whether it is safe to download would defeat the point.

private func darkGramSHA256(path: String) -> String? {
    // Mapped rather than read: a video of a few gigabytes is paged in as the hash walks it,
    // instead of being loaded into memory at once.
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else {
        return nil
    }
    return SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
}

func darkGramCanShowFileHash(_ file: TelegramMediaFile) -> Bool {
    return !file.isSticker && !file.isAnimatedSticker && !file.isCustomEmoji
}

func darkGramShowFileHash(
    controllerInteraction: ChatControllerInteraction,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    context: AccountContext,
    file: TelegramMediaFile
) {
    let strings = chatPresentationInterfaceState.strings
    let lang = strings.baseLanguageCode
    let mediaBox = context.account.postbox.mediaBox

    let signal: Signal<String?, NoError> = Signal<String?, NoError> { subscriber in
        if let path = mediaBox.completedResourcePath(file.resource) {
            subscriber.putNext(darkGramSHA256(path: path))
        } else {
            subscriber.putNext(nil)
        }
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
    |> deliverOnMainQueue

    let _ = signal.startStandalone(next: { hash in
        guard let hash = hash else {
            controllerInteraction.presentController(textAlertController(
                context: context,
                title: nil,
                text: i18n("FileHash.NotDownloaded", lang),
                actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]
            ), nil)
            return
        }
        var text = hash
        if let name = file.fileName, !name.isEmpty {
            text = name + "\n\n" + hash
        }
        controllerInteraction.presentController(textAlertController(
            context: context,
            title: "SHA-256",
            text: text,
            actions: [
                TextAlertAction(type: .genericAction, title: i18n("FileHash.Copy", lang), action: {
                    UIPasteboard.general.string = hash
                }),
                TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})
            ]
        ), nil)
    })
}
