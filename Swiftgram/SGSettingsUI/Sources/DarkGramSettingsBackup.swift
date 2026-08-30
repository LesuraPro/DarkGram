import Foundation
import UIKit
import UniformTypeIdentifiers
import SGSimpleSettings
import SGStrings

// MARK: DarkGram
// Settings backup UI. A free Apple ID signature expires after seven days, so the app is
// reinstalled constantly and every toggle resets. Export writes one JSON file through the
// system share sheet; import reads it back through the document picker.
//
// Plain UIKit rather than Telegram's controller stack: this module has no dependency on the
// app's presentation layer, and adding one for two dialogs would not pay for itself.

private func darkGramTopViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        ?? UIApplication.shared.windows.first
    var controller = keyWindow?.rootViewController
    // Walk to the frontmost presented controller, or the picker appears behind whatever is open.
    while let presented = controller?.presentedViewController {
        controller = presented
    }
    return controller
}

private func darkGramShowBackupResult(message: String) {
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    presenter.present(alert, animated: true)
}

/// Writes the current settings to a temporary file and offers the system share sheet.
public func darkGramExportSettings(lang: String) {
    guard let data = SGSimpleSettings.shared.exportToJSON() else {
        darkGramShowBackupResult(message: "SettingsBackup.Export.Failed".i18n(lang))
        return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("DarkGram-settings.json")
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        darkGramShowBackupResult(message: "SettingsBackup.Export.Failed".i18n(lang))
        return
    }
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // Required on iPad, where a share sheet without an anchor crashes.
    activity.popoverPresentationController?.sourceView = presenter.view
    activity.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0
    )
    presenter.present(activity, animated: true)
}

/// Opens the document picker and restores whatever known settings the chosen file holds.
public func darkGramImportSettings(lang: String) {
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
    } else {
        picker = UIDocumentPickerViewController(documentTypes: ["public.json"], in: .open)
    }
    let coordinator = DarkGramSettingsImportCoordinator(lang: lang)
    picker.delegate = coordinator
    // The picker holds no strong reference to its delegate, so park it until dismissal.
    DarkGramSettingsImportCoordinator.active = coordinator
    presenter.present(picker, animated: true)
}

final class DarkGramSettingsImportCoordinator: NSObject, UIDocumentPickerDelegate {
    static var active: DarkGramSettingsImportCoordinator?

    private let lang: String

    init(lang: String) {
        self.lang = lang
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer { DarkGramSettingsImportCoordinator.active = nil }
        guard let url = urls.first else {
            return
        }
        // Files outside the app's own container need a security scope held for the read.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            darkGramShowBackupResult(message: "SettingsBackup.Import.Failed".i18n(self.lang))
            return
        }
        let applied = SGSimpleSettings.shared.importFromJSON(data)
        if applied > 0 {
            darkGramShowBackupResult(message: "SettingsBackup.Import.Done".i18n(self.lang))
        } else {
            darkGramShowBackupResult(message: "SettingsBackup.Import.Failed".i18n(self.lang))
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        DarkGramSettingsImportCoordinator.active = nil
    }
}

// MARK: DarkGram
/// Shows why the previous run ended badly, if it did. Debugging this fork means an hour-long
/// build followed by an install that costs one of ten weekly App IDs, so knowing whether the
/// last failure was an exception or a silent termination is worth a great deal.
public func darkGramShowDiagnostics(lang: String) {
    guard let presenter = darkGramTopViewController() else {
        return
    }
    let report = DarkGramDiagnostics.shared.lastFailureReport()
    let alert = UIAlertController(
        title: "SettingsBackup.Diagnostics.Title".i18n(lang),
        message: report ?? "SettingsBackup.Diagnostics.Clean".i18n(lang),
        preferredStyle: .alert
    )
    if let report = report {
        alert.addAction(UIAlertAction(title: "SettingsBackup.Diagnostics.Copy".i18n(lang), style: .default) { _ in
            UIPasteboard.general.string = report
        })
        alert.addAction(UIAlertAction(title: "SettingsBackup.Diagnostics.Clear".i18n(lang), style: .destructive) { _ in
            DarkGramDiagnostics.shared.clearReport()
        })
    }
    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
    presenter.present(alert, animated: true)
}
