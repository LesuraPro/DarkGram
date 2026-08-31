import Foundation
import UIKit
import SGSimpleSettings
import SGStrings
import TelegramCore
import AccountContext
import SwiftSignalKit

// MARK: DarkGram
//
// Two questions the app could never answer in one place.
//
// The first is what a stranger can see about you. Telegram has the settings, spread over a
// dozen screens, each showing its own value and none showing the total. Nobody audits twelve
// screens, so the answer in practice is "I assume it's fine".
//
// The second is whether the proxy is actually carrying this connection. The proxy screen shows
// what is configured, which is not the same thing: a proxy that failed and fell back leaves the
// setting switched on and the traffic direct. The connection itself knows, and now says so.

/// Reads the account's privacy settings and reports what is exposed.
public func darkGramShowPrivacyAudit(context: AccountContext, lang: String) {
    let _ = (context.engine.privacy.requestAccountPrivacySettings()
    |> deliverOnMainQueue).startStandalone(next: { settings in
        var exposed: [String] = []
        var hidden: [String] = []

        func classify(_ setting: SelectivePrivacySettings, _ key: String) {
            let name = i18n(key, lang)
            switch setting {
            case .enableEveryone:
                exposed.append(name)
            case .enableContacts, .disableEveryone:
                hidden.append(name)
            }
        }

        classify(settings.presence, "Privacy.LastSeen")
        classify(settings.profilePhoto, "Privacy.Photo")
        classify(settings.forwards, "Privacy.Forwards")
        classify(settings.phoneNumber, "Privacy.Phone")
        classify(settings.groupInvitations, "Privacy.Groups")
        classify(settings.voiceCalls, "Privacy.Calls")
        classify(settings.voiceMessages, "Privacy.VoiceMessages")
        classify(settings.bio, "Privacy.Bio")

        var body = ""
        if exposed.isEmpty {
            body += i18n("Privacy.Audit.None", lang)
        } else {
            body += i18n("Privacy.Audit.Exposed", lang) + "\n- " + exposed.joined(separator: "\n- ")
        }
        if settings.phoneDiscoveryEnabled {
            body += "\n\n" + i18n("Privacy.Audit.Discovery", lang)
        }
        if !hidden.isEmpty {
            body += "\n\n" + i18n("Privacy.Audit.Hidden", lang) + " " + String(hidden.count)
        }

        darkGramPresentAlert(title: i18n("Privacy.Audit.Title", lang), message: body)
    })
}

/// Reports what the current connection is actually doing, rather than what is configured.
public func darkGramShowConnectionInfo(context: AccountContext, lang: String) {
    let _ = (context.account.network.connectionStatus
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { status in
        var lines: [String] = []

        let state: String
        var proxyAddress: String?
        switch status {
        case .waitingForNetwork:
            state = i18n("Connection.State.NoNetwork", lang)
        case let .connecting(address, _):
            state = i18n("Connection.State.Connecting", lang)
            proxyAddress = address
        case let .updating(address):
            state = i18n("Connection.State.Updating", lang)
            proxyAddress = address
        case let .online(address):
            state = i18n("Connection.State.Online", lang)
            proxyAddress = address
        }
        lines.append(i18n("Connection.State", lang) + ": " + state)
        lines.append(i18n("Connection.Datacenter", lang) + ": DC" + String(context.account.network.datacenterId))

        // The distinction that matters: configured is not the same as carrying the traffic.
        if let proxyAddress = proxyAddress, !proxyAddress.isEmpty {
            lines.append(i18n("Connection.Proxy.Active", lang) + ": " + proxyAddress)
        } else {
            lines.append(i18n("Connection.Proxy.Direct", lang))
        }

        darkGramPresentAlert(title: i18n("Connection.Title", lang), message: lines.joined(separator: "\n"))
    })
}

private func darkGramPresentAlert(title: String, message: String) {
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
    presenter.present(alert, animated: true)
}
