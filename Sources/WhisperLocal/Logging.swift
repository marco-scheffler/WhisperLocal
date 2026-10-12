import Foundation
import Combine
import os

struct LogEntry: Identifiable, Equatable {
    enum Level: String {
        case info, warn, error
    }
    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    var timeString: String {
        Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []
    private let capacity: Int = 500

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var asText: String {
        entries.map { "\($0.timeString) [\($0.level.rawValue.uppercased())] \($0.message)" }
            .joined(separator: "\n")
    }
}

/// Lightweight logger used throughout the app. Writes to both the unified
/// system log (for Console.app) and the in-app `LogStore` (visible in
/// Settings → Logs).
enum Log {
    private static let logger = Logger(subsystem: "io.github.marco-scheffler.WhisperLocal", category: "app")

    static func info(_ msg: @autoclosure () -> String) { write(.info, msg()) }
    static func warn(_ msg: @autoclosure () -> String) { write(.warn, msg()) }
    static func error(_ msg: @autoclosure () -> String) { write(.error, msg()) }

    /// For messages containing dictated text. The unified log persists on disk
    /// and is readable by any admin via `log show`, so the message is redacted
    /// there; the in-memory `LogStore` still shows it in full.
    static func sensitive(_ msg: @autoclosure () -> String) { write(.info, msg(), sensitive: true) }

    private static func write(_ level: LogEntry.Level, _ message: String, sensitive: Bool = false) {
        let type: OSLogType = level == .info ? .default : .error
        if sensitive {
            logger.log(level: type, "[\(level.rawValue, privacy: .public)] \(message, privacy: .private)")
        } else {
            logger.log(level: type, "[\(level.rawValue, privacy: .public)] \(message, privacy: .public)")
        }
        let entry = LogEntry(date: Date(), level: level, message: message)
        if Thread.isMainThread {
            MainActor.assumeIsolated { LogStore.shared.append(entry) }
        } else {
            Task { @MainActor in LogStore.shared.append(entry) }
        }
    }
}
