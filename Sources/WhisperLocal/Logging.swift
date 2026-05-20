import Foundation
import Combine

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

/// Lightweight logger used throughout the app. Writes to both `NSLog` (for
/// Console.app) and the in-app `LogStore` (visible in Settings → Logs).
enum Log {
    static func info(_ msg: @autoclosure () -> String) { write(.info, msg()) }
    static func warn(_ msg: @autoclosure () -> String) { write(.warn, msg()) }
    static func error(_ msg: @autoclosure () -> String) { write(.error, msg()) }

    private static func write(_ level: LogEntry.Level, _ message: String) {
        NSLog("[\(level.rawValue)] \(message)")
        let entry = LogEntry(date: Date(), level: level, message: message)
        if Thread.isMainThread {
            MainActor.assumeIsolated { LogStore.shared.append(entry) }
        } else {
            Task { @MainActor in LogStore.shared.append(entry) }
        }
    }
}
