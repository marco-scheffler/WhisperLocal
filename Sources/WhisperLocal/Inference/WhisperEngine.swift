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

    /// Receives the progress fraction (0.0–1.0) while the model is downloading.
    /// Called on an unspecified actor — hop to MainActor before touching UI.
    var onDownloadProgress: (@Sendable (Double) -> Void)?
    /// Called when download finishes and load starts.
    var onLoadStarted: (@Sendable () -> Void)?
    /// Called when the model is fully ready.
    var onReady: (@Sendable () -> Void)?

    init(modelStore: ModelStore, modelName: String = "large-v3-v20240930_626MB") {
        self.modelStore = modelStore
        self.modelName = modelName
    }

    func setProgressHandlers(
        onDownloadProgress: (@Sendable (Double) -> Void)? = nil,
        onLoadStarted: (@Sendable () -> Void)? = nil,
        onReady: (@Sendable () -> Void)? = nil
    ) {
        self.onDownloadProgress = onDownloadProgress
        self.onLoadStarted = onLoadStarted
        self.onReady = onReady
    }

    func ensureLoaded() async throws {
        if pipelineBox != nil { return }

        let modelFolderURL: URL
        let expectedFolderName = "openai_whisper-\(modelName)"
        let candidate = modelStore.whisperModelDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(expectedFolderName)")

        if FileManager.default.fileExists(atPath: candidate.path) {
            Log.info("WhisperEngine:reusing cached model at \(candidate.path)")
            modelFolderURL = candidate
        } else {
            Log.info("WhisperEngine:downloading model \(modelName)")
            let progressCallback = onDownloadProgress
            modelFolderURL = try await WhisperKit.download(
                variant: modelName,
                downloadBase: modelStore.whisperModelDirectory,
                from: "argmaxinc/whisperkit-coreml"
            ) { progress in
                progressCallback?(progress.fractionCompleted)
            }
            Log.info("WhisperEngine:download complete at \(modelFolderURL.path)")
        }

        onLoadStarted?()
        Log.info("WhisperEngine:loading WhisperKit pipeline")
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolderURL.path,
            verbose: true,
            logLevel: .info,
            load: true,
            download: false
        )
        do {
            pipelineBox = WhisperKitBox(try await WhisperKit(config))
            Log.info("WhisperEngine:model ready")
            onReady?()
        } catch {
            Log.info("WhisperEngine:model load failed: \(error)")
            throw error
        }
    }

    /// Eagerly download + load the model. Safe to call at app launch.
    func warmup() async throws {
        try await ensureLoaded()
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        try await ensureLoaded()
        guard let box = pipelineBox else { return "" }
        Log.info("WhisperEngine:transcribing \(samples.count) samples (\(Double(samples.count)/16000.0)s)")
        let options = DecodingOptions(language: language)
        do {
            let results = try await box.value.transcribe(audioArray: samples, decodeOptions: options)
            let text = results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Log.info("WhisperEngine:transcript = \(text)")
            return text
        } catch {
            Log.info("WhisperEngine:transcribe failed: \(error)")
            throw error
        }
    }
}
