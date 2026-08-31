import Foundation
import SGSimpleSettings
import Postbox
import TelegramCore


func sgDoubleTapMessageAction(incoming: Bool, message: Message) -> String {
    if incoming {
        // MARK: DarkGram - upstream hardcoded the reaction here; now it is a setting like outgoing.
        return SGSimpleSettings.shared.messageDoubleTapActionIncoming
    } else {
        return SGSimpleSettings.shared.messageDoubleTapActionOutgoing
    }
}

func sgHandleDoubleTapMessageAction(
    incoming: Bool,
    message: Message,
    editAction: () -> Void,
    // MARK: DarkGram - reply and copy, the two things a double tap is actually wanted for.
    replyAction: () -> Void = {},
    copyAction: () -> Void = {},
    defaultAction: () -> Void
) {
    switch sgDoubleTapMessageAction(incoming: incoming, message: message) {
    case SGSimpleSettings.MessageDoubleTapAction.none.rawValue:
        break
    case SGSimpleSettings.MessageDoubleTapAction.edit.rawValue:
        // Only the author can edit, so fall back rather than doing nothing on someone else's message.
        if incoming {
            defaultAction()
        } else {
            editAction()
        }
    case SGSimpleSettings.MessageDoubleTapAction.reply.rawValue:
        replyAction()
    case SGSimpleSettings.MessageDoubleTapAction.copy.rawValue:
        copyAction()
    default:
        defaultAction()
    }
}
