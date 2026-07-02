import Foundation
import SwiftData
import os

/// Central `os.Logger` instances — one category per subsystem area.
///
/// Usage: `Log.network.error("probe failed: \(error.localizedDescription, privacy: .public)")`.
/// Entries appear live in Console.app (filter on the subsystem) or after the fact:
///
///     /usr/bin/log show --last 1h --predicate 'subsystem == "com.peregrine.modelo"'
///
/// Dynamic values are redacted in release builds unless marked `privacy: .public`;
/// error messages here are marked public so failures stay diagnosable in the field.
enum Log {
    private static let subsystem = "com.peregrine.modelo"

    /// App lifecycle: launch, store setup, scenes.
    static let app = Logger(subsystem: subsystem, category: "app")
    /// SwiftData store: opens, saves, migrations, retention pruning.
    static let data = Logger(subsystem: subsystem, category: "data")
    /// Chat turns: streaming, tool rounds, compaction, titling.
    static let chat = Logger(subsystem: subsystem, category: "chat")
    /// HTTP to model servers (LM Studio, Ollama, OpenRouter) and web tools.
    static let network = Logger(subsystem: subsystem, category: "network")
    /// Built-in tool execution (filesystem, benchmark, …).
    static let tools = Logger(subsystem: subsystem, category: "tools")
    /// MCP server lifecycle and calls.
    static let mcp = Logger(subsystem: subsystem, category: "mcp")
    /// Polling monitors: GPU, server stats, Prometheus, reachability.
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    /// Post-mortem diagnostics delivered by MetricKit (see `CrashReporter`).
    static let crash = Logger(subsystem: subsystem, category: "crash")
}

extension ModelContext {
    /// Saves like `try? save()`, but logs a failure instead of discarding it.
    ///
    /// Most call sites treat saves as best-effort and shouldn't change control flow
    /// on failure — but a failing store write was previously invisible. This keeps
    /// the fire-and-forget shape while leaving a trail.
    /// - Parameter caller: The calling function, captured automatically for the log line.
    func saveOrLog(caller: String = #function) {
        do {
            try save()
        } catch {
            Log.data.error("save failed in \(caller, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
