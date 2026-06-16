//
//  Log.swift
//  Screenish
//
//  Lightweight logging + persistent crash capture. The app is a menu-bar agent
//  (LSUIElement) launched from Finder, so it has no terminal and macOS shows no
//  crash dialog — a stderr-only handler leaves the user with nothing. Instead we
//  keep a persistent per-session log on disk under ~/Library/Logs/Screenish/,
//  drop breadcrumbs as the app works, and on the next launch detect that the
//  previous session never shut down cleanly, promote its log to a crash report,
//  and pull in Apple's symbolicated .ips. The user can then hand the folder over.
//

import Foundation
import AppKit
import OSLog
import Darwin

// MARK: - C-accessible crash state
//
// Signal handlers must be non-capturing @convention(c) functions, so the file
// descriptor and scratch buffers live at file scope. Everything the *handler*
// touches is async-signal-safe (write/fsync/backtrace_symbols_fd + a pre-opened
// fd and pre-allocated buffers). All allocation happens earlier, at install time.

private var gCrashFD: Int32 = -1
private let gBacktraceCapacity = 128
private let gBacktraceBuffer =
    UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: gBacktraceCapacity)
private let gSignalBannerBytes =
    Array("\n*** SCREENISH CRASHED (fatal signal) — backtrace follows ***\n".utf8)

/// Async-signal-safe: writes a fixed banner + raw backtrace to the pre-opened fd,
/// then restores the default disposition and re-raises so macOS still produces a
/// full .ips report.
private func screenishCrashSignalHandler(_ sig: Int32) {
    if gCrashFD >= 0 {
        gSignalBannerBytes.withUnsafeBytes { _ = write(gCrashFD, $0.baseAddress, $0.count) }
        let n = backtrace(gBacktraceBuffer, Int32(gBacktraceCapacity))
        backtrace_symbols_fd(gBacktraceBuffer, n, gCrashFD)
        fsync(gCrashFD)
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

enum Log {
    static let general = Logger(subsystem: "stcloud.se.Screenish", category: "general")
    static let drag = Logger(subsystem: "stcloud.se.Screenish", category: "drag")
    static let render = Logger(subsystem: "stcloud.se.Screenish", category: "render")

    /// Install persistent crash capture. Call once, early in launch.
    static func installCrashHandlers() {
        CrashReporter.install()
    }

    /// Record a timestamped breadcrumb to the session log (and OSLog) so a later
    /// crash report shows what the app was doing right before it died.
    static func breadcrumb(_ message: String) {
        CrashReporter.breadcrumb(message)
    }
}

enum CrashReporter {
    /// ~/Library/Logs/Screenish — where session logs, promoted crash reports and
    /// collected .ips files live. Surfaced to the user via the tray menu.
    static let logDirectory: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/Screenish", isDirectory: true)
    }()

    private static let sessionURL = logDirectory.appendingPathComponent("current-session.log")
    private static let cleanMarker = "=== CLEAN SHUTDOWN ===\n"
    /// Common prefix of every banner our signal/exception handlers write. A
    /// previous session is a crash iff its log contains this — so a graceful kill
    /// (SIGTERM on logout/force-quit), which writes no banner, is not misreported.
    private static let crashSentinel = "*** SCREENISH"

    /// True if the previous session ended without a clean-shutdown marker (i.e. it
    /// crashed or was killed). Read once at launch to decide whether to notify.
    private(set) static var lastSessionCrashed = false

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func install() {
        try? FileManager.default.createDirectory(
            at: logDirectory, withIntermediateDirectories: true)

        // Inspect the *previous* session before we truncate it for this run.
        promotePreviousSessionIfCrashed()

        // ReportCrash writes the .ips asynchronously — it often isn't on disk yet
        // on the immediate relaunch, so sweep every launch and copy anything new.
        collectAppleReports()
        prune()

        // Open (truncate) the session file and keep the fd for the handlers.
        gCrashFD = open(sessionURL.path,
                        O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o644)
        writeHeader()

        installSignalHandlers()
        installExceptionHandler()
    }

    // MARK: - Session file

    private static func writeHeader() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let header = """
        ===== Screenish session =====
        version: \(version) (\(build))
        macOS:   \(ProcessInfo.processInfo.operatingSystemVersionString)
        date:    \(timestampFormatter.string(from: Date()))
        pid:     \(ProcessInfo.processInfo.processIdentifier)
        =============================

        """
        rawWrite(header)
    }

    static func breadcrumb(_ message: String) {
        Log.general.log("\(message, privacy: .public)")
        rawWrite("[\(timestampFormatter.string(from: Date()))] \(message)\n")
    }

    /// Append a clean-shutdown marker and close the fd. Call from
    /// applicationWillTerminate so a normal quit isn't mistaken for a crash.
    static func markCleanShutdown() {
        rawWrite(cleanMarker)
        if gCrashFD >= 0 {
            fsync(gCrashFD)
            close(gCrashFD)
            gCrashFD = -1
        }
    }

    private static func rawWrite(_ text: String) {
        guard gCrashFD >= 0 else { return }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBytes { _ = write(gCrashFD, $0.baseAddress, $0.count) }
    }

    // MARK: - Crash detection / promotion

    private static func promotePreviousSessionIfCrashed() {
        guard let previous = try? String(contentsOf: sessionURL, encoding: .utf8),
              !previous.isEmpty else { return }
        guard previous.contains(crashSentinel) else { return }  // no crash banner

        lastSessionCrashed = true
        let stamp = Int(Date().timeIntervalSince1970)
        let crashURL = logDirectory.appendingPathComponent("crash-\(stamp).log")
        try? previous.write(to: crashURL, atomically: true, encoding: .utf8)
        Log.general.fault("previous session crashed; saved \(crashURL.lastPathComponent, privacy: .public)")
    }

    /// Copy Apple's symbolicated crash reports (the real signal-level diagnosis)
    /// into our folder so everything the user needs sits in one place. Runs every
    /// launch and only copies reports we don't already have — late-written .ips
    /// files therefore get picked up on the next launch. Keeps only recent ones.
    private static func collectAppleReports(keep: Int = 10) {
        let fm = FileManager.default
        let reportsDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: reportsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }

        let reports = entries.filter {
            $0.lastPathComponent.hasPrefix("Screenish")
                && ["ips", "crash"].contains($0.pathExtension)
        }.compactMap { url -> (URL, Date)? in
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            return d.map { (url, $0) }
        }.sorted { $0.1 > $1.1 }

        for (src, _) in reports.prefix(keep) {
            let dest = logDirectory.appendingPathComponent(src.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: src, to: dest)
                Log.general.log("collected Apple report \(src.lastPathComponent, privacy: .public)")
            }
        }
    }

    /// Keep only the most recent crash artifacts so the folder doesn't grow without
    /// bound (current-session.log is excluded — it's the live file). Prunes our own
    /// promoted logs and the collected Apple reports independently.
    private static func prune(keep: Int = 10) {
        for prefix in ["crash-", "Screenish-"] {
            pruneFiles(withPrefix: prefix, keep: keep)
        }
    }

    private static func pruneFiles(withPrefix prefix: String, keep: Int) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let files = entries
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .compactMap { url -> (URL, Date)? in
                let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return d.map { (url, $0) }
            }
            .sorted { $0.1 > $1.1 }
        for (url, _) in files.dropFirst(keep) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Handlers

    private static func installSignalHandlers() {
        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGTRAP, SIGBUS, SIGFPE] {
            signal(sig, screenishCrashSignalHandler)
        }
    }

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let trace = exception.callStackSymbols.joined(separator: "\n")
            let text = "\n*** SCREENISH UNCAUGHT EXCEPTION: "
                + "\(exception.name.rawValue): \(exception.reason ?? "")\n\(trace)\n"
            if gCrashFD >= 0 {
                let bytes = Array(text.utf8)
                bytes.withUnsafeBytes { _ = write(gCrashFD, $0.baseAddress, $0.count) }
                fsync(gCrashFD)
            }
            Log.general.fault("UNCAUGHT EXCEPTION \(exception.name.rawValue, privacy: .public): \(exception.reason ?? "", privacy: .public)\n\(trace, privacy: .public)")
        }
    }

    /// Reveal the crash-log folder in Finder (wired to the tray menu).
    static func revealInFinder() {
        try? FileManager.default.createDirectory(
            at: logDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logDirectory])
    }
}
