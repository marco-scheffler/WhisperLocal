import Combine

enum OverlayPhase: Equatable {
    case hidden
    case downloadingModel(progress: Double)
    case loadingModel
    case recording
    case transcribing
    case postProcessing
    case injecting
    case error(String)
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .hidden
    @Published var level: Float = 0
    @Published var partialText: String = ""
}
