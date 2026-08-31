import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import PresentationDataUtils
import SGSimpleSettings
import SGStrings

// MARK: DarkGram
//
// Tells you when a session appears that was not there before.
//
// Telegram already lists active sessions, but the list only speaks when opened. An account is
// normally taken over quietly, and by the time anyone thinks to look at that screen the
// interesting part has already happened. This watches on every launch and says something the
// first time a session it has not seen before shows up.
//
// The first run only records. Alerting about the sessions that already existed would say
// nothing about a compromise and would train the alert to be ignored, which is worse than not
// having it at all.

private final class DarkGramSessionWatch {
    static let shared = DarkGramSessionWatch()

    private let disposable = MetaDisposable()
    /// The context stops loading once released, so it has to outlive the call that made it.
    private var sessionsContext: ActiveSessionsContext?
    private var checkedThisLaunch = false

    func check(context: AccountContext, present: @escaping (ViewController) -> Void) {
        assert(Queue.mainQueue().isCurrent())

        guard SGSimpleSettings.shared.sessionWatchEnabled, !self.checkedThisLaunch else {
            return
        }
        self.checkedThisLaunch = true

        let sessionsContext = context.engine.privacy.activeSessions()
        self.sessionsContext = sessionsContext

        self.disposable.set((sessionsContext.state
        |> filter { state in
            // The context publishes an empty placeholder before the request lands.
            return !state.isLoadingMore && !state.sessions.isEmpty
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.report(sessions: state.sessions, context: context, present: present)
            self?.sessionsContext = nil
        }))
    }

    private func report(sessions: [RecentAccountSession], context: AccountContext, present: @escaping (ViewController) -> Void) {
        let lang = context.sharedContext.currentPresentationData.with({ $0 }).strings.baseLanguageCode
        let known = darkGramKnownSessionHashes()

        // Record first: if presenting fails, the same session must not alert forever.
        SGSimpleSettings.shared.knownSessionHashes = sessions.map({ String($0.hash) }).joined(separator: ",")

        guard !known.isEmpty else {
            return
        }
        let appeared = sessions.filter { session in
            return !session.isCurrent && !known.contains(session.hash)
        }
        guard !appeared.isEmpty else {
            return
        }

        var lines: [String] = []
        for session in appeared {
            var line = session.deviceModel
            if !session.appName.isEmpty {
                line += " - " + session.appName
            }
            var origin = session.country
            if !session.ip.isEmpty {
                origin = origin.isEmpty ? session.ip : origin + ", " + session.ip
            }
            if !origin.isEmpty {
                line += "\n" + origin
            }
            lines.append(line)
        }

        let controller = textAlertController(
            context: context,
            title: i18n("SessionWatch.Title", lang),
            text: i18n("SessionWatch.Text", lang) + "\n\n" + lines.joined(separator: "\n\n"),
            actions: [
                TextAlertAction(type: .genericAction, title: i18n("SessionWatch.Dismiss", lang), action: {})
            ]
        )
        present(controller)
    }
}

private func darkGramKnownSessionHashes() -> Set<Int64> {
    let stored = SGSimpleSettings.shared.knownSessionHashes
    guard !stored.isEmpty else {
        return Set()
    }
    return Set(stored.split(separator: ",").compactMap({ Int64($0) }))
}

func darkGramCheckForNewSessions(context: AccountContext, present: @escaping (ViewController) -> Void) {
    DarkGramSessionWatch.shared.check(context: context, present: present)
}
