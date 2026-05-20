import Combine
import Foundation

@MainActor
final class ModelStatus: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var modelName: String = ""

    var statusText: String {
        switch phase {
        case .idle: return "Not started"
        case .downloading(let p): return String(format: "Downloading %.0f%%", p * 100)
        case .loading: return "Loading\u{2026}"
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
