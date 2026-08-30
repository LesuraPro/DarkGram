import Foundation

// MARK: DarkGram
// Local crash diagnostics.
//
// This fork is debugged blind: builds take an hour, there is no crash reporter wired
// (app_center_id is "0"), and a failure on device arrives as "it does not open" with nothing
// else. That is expensive. This records just enough to answer the first question -- did the
// last run end badly, and was there an exception -- without a reporting service.
//
// Deliberately no signal handlers. Catching SIGSEGV correctly is delicate, an incorrect handler
// makes crashes worse rather than clearer, and the unclean-exit flag already covers the cases
// signals would -- including watchdog kills, which raise no signal at all.

public final class DarkGramDiagnostics {
    public static let shared = DarkGramDiagnostics()

    private let runningKey = "darkgram.diag.running"
    private let exceptionKey = "darkgram.diag.lastException"
    private let crashedAtKey = "darkgram.diag.lastUncleanExit"

    /// True when the previous run did not shut down cleanly: a crash, or a watchdog kill.
    public private(set) var previousRunEndedBadly = false

    private init() {}

    /// Call once at launch, before anything else can fail.
    public func begin() {
        let defaults = UserDefaults.standard
        // A flag still set from last time means that run never reached its clean exit.
        self.previousRunEndedBadly = defaults.bool(forKey: self.runningKey)
        if self.previousRunEndedBadly {
            defaults.set(Date().timeIntervalSince1970, forKey: self.crashedAtKey)
        }
        defaults.set(true, forKey: self.runningKey)

        NSSetUncaughtExceptionHandler { exception in
            // Anything richer than this risks failing inside the handler itself.
            let text = [
                exception.name.rawValue,
                exception.reason ?? "",
                exception.callStackSymbols.prefix(24).joined(separator: "\n"),
            ].joined(separator: "\n")
            UserDefaults.standard.set(text, forKey: "darkgram.diag.lastException")
            UserDefaults.standard.synchronize()
        }
    }

    /// Call when the app terminates or goes to the background.
    public func markCleanExit() {
        UserDefaults.standard.set(false, forKey: self.runningKey)
    }

    /// Human-readable summary of the last bad exit, or nil when the last run was fine.
    public func lastFailureReport() -> String? {
        let defaults = UserDefaults.standard
        let exception = defaults.string(forKey: self.exceptionKey)
        guard self.previousRunEndedBadly || exception != nil else {
            return nil
        }
        var lines: [String] = []
        let when = defaults.double(forKey: self.crashedAtKey)
        if when > 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            lines.append(formatter.string(from: Date(timeIntervalSince1970: when)))
        }
        if let exception = exception, !exception.isEmpty {
            lines.append(exception)
        } else {
            // No exception recorded: the process died without unwinding -- a memory fault, a
            // watchdog timeout, or the system reclaiming memory.
            lines.append("No exception was recorded. The process was terminated without unwinding: a memory fault, a watchdog timeout, or the system reclaiming memory.")
        }
        return lines.joined(separator: "\n\n")
    }

    public func clearReport() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: self.exceptionKey)
        defaults.removeObject(forKey: self.crashedAtKey)
        self.previousRunEndedBadly = false
    }
}

// MARK: DarkGram
/// Sideloading with a free Apple ID gives a seven-day signature. The app otherwise just stops
/// opening one morning with no warning, so surface the remaining time.
///
/// The bundle's creation date is the install date, which is when the signature was issued --
/// closer to the truth than the build date, since a build can sit in Releases for days.
public enum DarkGramSignature {
    public static let validityDays = 7

    public static var daysRemaining: Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundlePath),
              let installed = attributes[.creationDate] as? Date else {
            return nil
        }
        let expiry = installed.addingTimeInterval(Double(validityDays) * 24 * 60 * 60)
        let seconds = expiry.timeIntervalSinceNow
        if seconds <= 0 {
            return 0
        }
        return Int(ceil(seconds / (24 * 60 * 60)))
    }
}
