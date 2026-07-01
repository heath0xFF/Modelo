import Foundation
import MetricKit

/// Receives MetricKit diagnostic payloads (crashes and hangs) that the OS delivers
/// on the next launch after an incident, logs a one-line summary, and archives the
/// full JSON — so post-mortem evidence survives even when no debugger was attached
/// and no crash dialog appeared.
///
/// Archived payloads land in `~/Library/Application Support/Modelo/Diagnostics/`.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    /// Where full diagnostic payloads are archived for later inspection.
    private static let archiveFolder = URL.applicationSupportDirectory
        .appending(path: "Modelo", directoryHint: .isDirectory)
        .appending(path: "Diagnostics", directoryHint: .isDirectory)

    /// Subscribes to MetricKit. Call once at launch; payloads for past incidents
    /// arrive asynchronously (typically within seconds of becoming subscribed).
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// MetricKit delivery callback — runs on a background queue.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                Log.crash.fault("Previous session crashed: \(Self.describe(crash), privacy: .public)")
            }
            for hang in payload.hangDiagnostics ?? [] {
                Log.crash.error("Previous session hang: \(hang.hangDuration.description, privacy: .public)")
            }
            archive(payload)
        }
    }

    /// One-line human summary of a crash diagnostic (exception type/code, signal,
    /// and termination reason where present).
    private static func describe(_ crash: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let type = crash.exceptionType { parts.append("exception type \(type)") }
        if let code = crash.exceptionCode { parts.append("code \(code)") }
        if let signal = crash.signal { parts.append("signal \(signal)") }
        if let reason = crash.terminationReason { parts.append(reason) }
        return parts.isEmpty ? "unknown cause" : parts.joined(separator: ", ")
    }

    /// Writes the payload's full JSON to the archive folder, named by incident time.
    private func archive(_ payload: MXDiagnosticPayload) {
        do {
            try FileManager.default.createDirectory(at: Self.archiveFolder, withIntermediateDirectories: true)
            // Colons render as "/" in Finder; keep the timestamp filename-safe.
            let stamp = ISO8601DateFormatter().string(from: payload.timeStampEnd)
                .replacingOccurrences(of: ":", with: "-")
            let file = Self.archiveFolder.appending(path: "diagnostic-\(stamp).json")
            try payload.jsonRepresentation().write(to: file)
            Log.crash.info("Archived diagnostic payload to \(file.path, privacy: .public)")
        } catch {
            Log.crash.error("Failed to archive diagnostic payload: \(error.localizedDescription, privacy: .public)")
        }
    }
}
