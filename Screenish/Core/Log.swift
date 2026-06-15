//
//  Log.swift
//  Screenish
//
//  Lightweight logging + crash/exception capture so intermittent failures
//  (e.g. during drag-and-drop) leave a stack trace in the console.
//

import Foundation
import OSLog

enum Log {
    static let general = Logger(subsystem: "stcloud.se.Screenish", category: "general")
    static let drag = Logger(subsystem: "stcloud.se.Screenish", category: "drag")
    static let render = Logger(subsystem: "stcloud.se.Screenish", category: "render")

    /// Install handlers that print a backtrace to stderr/console on crash.
    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let trace = exception.callStackSymbols.joined(separator: "\n")
            Log.general.fault("UNCAUGHT EXCEPTION \(exception.name.rawValue, privacy: .public): \(exception.reason ?? "", privacy: .public)\n\(trace, privacy: .public)")
            FileHandle.standardError.write(Data(
                "\n*** Screenish uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "")\n\(trace)\n".utf8))
        }

        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGTRAP, SIGBUS, SIGFPE] {
            signal(sig) { received in
                let trace = Thread.callStackSymbols.joined(separator: "\n")
                FileHandle.standardError.write(Data(
                    "\n*** Screenish crash (signal \(received)):\n\(trace)\n".utf8))
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
