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

    /// Push-to-talk: hold the hotkey while speaking. Toggle: tap to start, tap
    /// again (or stay silent for `silenceTimeoutSeconds`) to stop.
    var recordingMode: RecordingMode = .toggle

    /// Auto-stop threshold for toggle mode: stop after this many seconds with the
    /// audio level continuously below `silenceLevelThreshold`.
    var silenceTimeoutSeconds: TimeInterval = 2.0

    /// RMS level under which audio counts as silence.
    var silenceLevelThreshold: Float = 0.01

    /// Hard cap on recording duration in toggle mode (safety against runaway sessions).
    var maxRecordingSeconds: TimeInterval = 60

    private var silenceMonitor: Task<Void, Never>?
    private var levelSubscription: AnyCancellable?
    private var lastLoudAt: Date = Date()
    private var recordingStartedAt: Date = Date()

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
        switch recordingMode {
        case .pushToTalk:
            if pressed {
                await startRecording()
            } else {
                await stopAndProcess()
            }
        case .toggle:
            // React only to the press edge; ignore release.
            guard pressed else { return }
            if state == .idle {
                await startRecording()
            } else if state == .recording {
                Log.info("DictationController:manual toggle stop")
                await stopAndProcess()
            }
            // While transcribing/injecting, ignore taps to avoid double-triggering.
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
            if recordingMode == .toggle {
                startSilenceMonitor()
            }
        } catch {
            await fail(message: "Mic error: \(error.localizedDescription)")
        }
    }

    private func startSilenceMonitor() {
        recordingStartedAt = Date()
        lastLoudAt = Date()

        // Track the level on the main actor.
        levelSubscription = recorder.levelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                guard let self else { return }
                if level >= self.silenceLevelThreshold {
                    self.lastLoudAt = Date()
                }
            }

        silenceMonitor?.cancel()
        let silenceTimeout = silenceTimeoutSeconds
        let maxDuration = maxRecordingSeconds
        silenceMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200 ms
                guard let self else { return }
                if Task.isCancelled { return }
                let now = Date()
                let silenceFor = now.timeIntervalSince(self.lastLoudAt)
                let recordingFor = now.timeIntervalSince(self.recordingStartedAt)
                if self.state != .recording { return }
                if recordingFor > maxDuration {
                    Log.info("DictationController:max duration reached (\(maxDuration)s)")
                    await self.stopAndProcess()
                    return
                }
                // Require at least 1 s of recording before silence can trigger,
                // so a brief lead-in pause does not abort the take.
                if recordingFor > 1.0 && silenceFor >= silenceTimeout {
                    Log.info("DictationController:silence \(String(format: "%.2f", silenceFor))s — auto-stop")
                    await self.stopAndProcess()
                    return
                }
            }
        }
    }

    private func stopSilenceMonitor() {
        silenceMonitor?.cancel()
        silenceMonitor = nil
        levelSubscription?.cancel()
        levelSubscription = nil
    }

    private func stopAndProcess() async {
        guard state == .recording else { return }
        stopSilenceMonitor()
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
        stopSilenceMonitor()
        overlay.state.phase = .error(message)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await reset()
    }

    private func reset() async {
        state = .idle
        overlay.hide()
    }
}
