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
        let collected = body

        // MARK: DarkGram - the setting that matters more than all of the above together. Without
        // a password, the login code alone is the whole account; it goes first when missing.
        let _ = (context.engine.auth.twoStepVerificationConfiguration()
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { twoStep in
            var full = collected
            switch twoStep {
            case .notSet:
                full = i18n("Privacy.Audit.TwoStepOff", lang) + "\n\n" + full
            case let .set(_, hasRecoveryEmail, _, _, _):
                if !hasRecoveryEmail {
                    full += "\n\n" + i18n("Privacy.Audit.NoRecoveryEmail", lang)
                }
            }
            darkGramPresentAlert(title: i18n("Privacy.Audit.Title", lang), message: full)
        })
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

// MARK: DarkGram
//
// The user's own list of domains that are never opened. Edited as one line of text, because
// the list is short, copied from elsewhere, and a one-row-per-domain editor would be more
// screen than the job is worth.
public func darkGramEditBlockedDomains(lang: String) {
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let alert = UIAlertController(title: i18n("Settings.Protection.BlockedDomains", lang), message: i18n("Settings.Protection.BlockedDomains.Hint", lang), preferredStyle: .alert)
    alert.addTextField { field in
        field.text = SGSimpleSettings.shared.blockedDomains
        field.placeholder = "example.com, evil.example"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
    }
    alert.addAction(UIAlertAction(title: i18n("BlockedDomains.Cancel", lang), style: .cancel))
    alert.addAction(UIAlertAction(title: i18n("BlockedDomains.Save", lang), style: .default, handler: { [weak alert] _ in
        let value = alert?.textFields?.first?.text ?? ""
        SGSimpleSettings.shared.blockedDomains = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }))
    presenter.present(alert, animated: true)
}

// MARK: DarkGram
//
// Everything the protections noticed, newest first. Shown in an alert like the other reports:
// the list is capped, and a separate screen for it would be one more thing to keep working.
public func darkGramShowSecurityLog(lang: String) {
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let events = DarkGramSecurityLog.shared.events()
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM HH:mm"

    var lines: [String] = []
    for event in events.prefix(40) {
        let when = formatter.string(from: Date(timeIntervalSince1970: Double(event.timestamp)))
        var line = when + " — " + i18n("SecurityLog.Kind." + event.kind, lang)
        if !event.detail.isEmpty {
            line += ": " + event.detail
        }
        lines.append(line)
    }
    let message = lines.isEmpty ? i18n("SecurityLog.Empty", lang) : lines.joined(separator: "\n\n")

    let alert = UIAlertController(title: i18n("SecurityLog.Title", lang), message: message, preferredStyle: .alert)
    if !lines.isEmpty {
        alert.addAction(UIAlertAction(title: i18n("SecurityLog.Clear", lang), style: .destructive, handler: { _ in
            DarkGramSecurityLog.shared.clear()
        }))
    }
    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
    presenter.present(alert, animated: true)
}
