import Foundation
import WhisperKit

// WhisperKit is an open class without Sendable conformance.
// We wrap it in a Sendable box so we can pass it across Swift 6
// isolation boundaries. Access is serialized by the WhisperEngine actor.
private final class WhisperKitBox: @unchecked Sendable {
    let value: WhisperKit
    init(_ value: WhisperKit) { self.value = value }
}

actor WhisperEngine: Transcribing {
    private let modelName: String
    private let modelStore: ModelStore
    private var pipelineBox: WhisperKitBox?

    init(modelStore: ModelStore, modelName: String = "large-v3-v20240930_626MB") {
        self.modelStore = modelStore
        self.modelName = modelName
    }

    func ensureLoaded() async throws {
        if pipelineBox != nil { return }
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelStore.whisperModelDirectory.path,
            verbose: false,
            logLevel: .error,
            download: false
        )
        pipelineBox = WhisperKitBox(try await WhisperKit(config))
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        try await ensureLoaded()
        guard let box = pipelineBox else { return "" }
        let options = DecodingOptions(language: language)
        let results = try await box.value.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
