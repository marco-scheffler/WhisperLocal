import Foundation
import Combine

/// Central orchestrator for the record → transcribe → post-process → inject pipeline.
///
/// All state mutations happen on the `@MainActor` so the `@Published` properties
/// can be safely observed from SwiftUI without extra hops.
@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle, recording, transcribing, postProcessing, injecting
    }

    @Published private(set) var state: State = .idle

    private let recorder: any Recording
    private let transcriber: Transcribing
    private let postProcessor: (any TextCleaning)?
    private let injector: TextInjector
    private let overlay: OverlayWindow

    /// Set to `false` to skip LLM post-processing even when a `postProcessor` is available.
    var llmEnabled: Bool = true

    init(
        recorder: any Recording,
        transcriber: Transcribing,
        postProcessor: (any TextCleaning)?,
        injector: TextInjector,
        overlay: OverlayWindow
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.postProcessor = postProcessor
        self.injector = injector
        self.overlay = overlay
    }

    // MARK: - Public API

    func handleHotKey(pressed: Bool) async {
        if pressed {
            await startRecording()
        } else {
            await stopAndProcess()
        }
    }

    // MARK: - Private pipeline steps

    private func startRecording() async {
        guard state == .idle else { return }
        do {
            try recorder.start()
            state = .recording
            overlay.state.phase = .recording
            overlay.show()
        } catch {
            await fail(message: "Mic error: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess() async {
        guard state == .recording else { return }
        let samples = recorder.stop()
        let durationSeconds = Double(samples.count) / 16_000.0
        Log.info("DictationController:captured \(samples.count) samples (\(String(format: "%.2f", durationSeconds))s)")

        if samples.count < 16_000 / 2 { // less than 0.5 s of audio
            await fail(message: "Too short — hold longer")
            return
        }

        state = .transcribing
        overlay.state.phase = .transcribing

        let raw: String
        do {
            raw = try await transcriber.transcribe(samples: samples, language: Preferences.language)
        } catch {
            Log.info("DictationController:transcribe error: \(error)")
            await fail(message: "Transcribe failed: \(error.localizedDescription)")
            return
        }

        Log.info("DictationController:raw transcript=\"\(raw)\" (\(raw.count) chars)")

        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await fail(message: "No speech detected")
            return
        }

        var text = raw
        if llmEnabled, let post = postProcessor {
            state = .postProcessing
            overlay.state.phase = .postProcessing
            let cleaned = (try? await post.clean(text: raw)) ?? raw
            Log.info("DictationController:cleaned=\"\(cleaned)\"")
            text = cleaned
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await fail(message: "Empty after cleanup")
            return
        }

        state = .injecting
        overlay.state.phase = .injecting
        Log.info("DictationController:injecting \(text.count) chars")
        injector.inject(text)

        try? await Task.sleep(nanoseconds: 700_000_000)
        await reset()
    }

    private func fail(message: String) async {
        overlay.state.phase = .error(message)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await reset()
    }

    private func reset() async {
        state = .idle
        overlay.hide()
    }
}
