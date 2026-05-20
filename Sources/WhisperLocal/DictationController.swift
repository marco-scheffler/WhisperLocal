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
        state = .transcribing
        overlay.state.phase = .transcribing

        let raw: String
        do {
            raw = try await transcriber.transcribe(samples: samples, language: nil)
        } catch {
            await fail(message: "Transcribe failed")
            return
        }

        var text = raw
        if llmEnabled, let post = postProcessor {
            state = .postProcessing
            overlay.state.phase = .postProcessing
            text = (try? await post.clean(text: raw)) ?? raw
        }

        guard !text.isEmpty else {
            await reset()
            return
        }

        state = .injecting
        overlay.state.phase = .injecting
        injector.inject(text)

        try? await Task.sleep(nanoseconds: 600_000_000)
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
