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
        NSLog("WhisperEngine: loading model \(modelName) (downloadBase=\(modelStore.whisperModelDirectory.path))")
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: modelStore.whisperModelDirectory,
            verbose: true,
            logLevel: .info,
            load: true,
            download: true
        )
        do {
            pipelineBox = WhisperKitBox(try await WhisperKit(config))
            NSLog("WhisperEngine: model loaded")
        } catch {
            NSLog("WhisperEngine: model load failed: \(error)")
            throw error
        }
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        try await ensureLoaded()
        guard let box = pipelineBox else { return "" }
        NSLog("WhisperEngine: transcribing \(samples.count) samples (\(Double(samples.count)/16000.0)s)")
        let options = DecodingOptions(language: language)
        do {
            let results = try await box.value.transcribe(audioArray: samples, decodeOptions: options)
            let text = results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("WhisperEngine: transcript = \(text)")
            return text
        } catch {
            NSLog("WhisperEngine: transcribe failed: \(error)")
            throw error
        }
    }
}
