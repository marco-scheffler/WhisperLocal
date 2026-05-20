import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let modelStatus = ModelStatus()

    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let overlay = OverlayWindow()
    private var controller: DictationController?
    private var hotKeys: HotKeyManager?
    private var menuBar: MenuBarController?
    private var cancellables: Set<AnyCancellable> = []
    private let settingsWindow = SettingsWindow()

    private var whisper: WhisperEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        let modelStore = ModelStore()
        let whisper = WhisperEngine(modelStore: modelStore)
        self.whisper = whisper
        let llm = LLMPostProcessor()

        let c = DictationController(
            recorder: recorder,
            transcriber: whisper,
            postProcessor: llm,
            injector: injector,
            overlay: overlay
        )
        c.llmEnabled = Preferences.llmEnabled
        c.recordingMode = Preferences.recordingMode
        recorder.inputDeviceUID = Preferences.inputDeviceUID
        controller = c

        // Forward audio level to overlay state.
        recorder.levelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in self?.overlay.state.level = lvl }
            .store(in: &cancellables)

        // Reflect dictation state in the menu bar icon.
        c.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                let iconState: MenuBarController.IconState = {
                    switch state {
                    case .idle:                       return .idle
                    case .recording:                  return .recording
                    case .transcribing, .postProcessing, .injecting: return .working
                    }
                }()
                self?.menuBar?.apply(state: iconState)
            }
            .store(in: &cancellables)

        // Reflect model download state in the menu bar icon while idle.
        Self.modelStatus.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                if case .downloading = phase {
                    self.menuBar?.apply(state: .downloading)
                } else if self.controller?.state == .idle {
                    self.menuBar?.apply(state: .idle)
                }
            }
            .store(in: &cancellables)

        let mgr = HotKeyManager(binding: Preferences.hotkey)
        mgr.onPressed  = { Task { @MainActor in await c.handleHotKey(pressed: true) } }
        mgr.onReleased = { Task { @MainActor in await c.handleHotKey(pressed: false) } }
        hotKeys = mgr

        settingsWindow.onHotkeyChange = { [weak self] new in self?.hotKeys?.update(binding: new) }
        settingsWindow.onLLMChange = { [weak self] new in self?.controller?.llmEnabled = new }
        settingsWindow.onInputDeviceChange = { [weak self] uid in self?.recorder.inputDeviceUID = uid }
        settingsWindow.onRecordingModeChange = { [weak self] mode in self?.controller?.recordingMode = mode }

        NotificationCenter.default.addObserver(
            forName: .openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settingsWindow.show() }
        }

        Log.info("WhisperLocal launched")

        Self.modelStatus.modelName = "large-v3-v20240930_626MB"

        // Kick off model warmup so the first transcription does not stall on download.
        Task { [weak self] in
            guard let self else { return }
            let overlay = self.overlay
            let status = Self.modelStatus
            await whisper.setProgressHandlers(
                onDownloadProgress: { progress in
                    Task { @MainActor in
                        status.phase = .downloading(progress: progress)
                        overlay.state.phase = .downloadingModel(progress: progress)
                        overlay.show()
                    }
                },
                onLoadStarted: {
                    Task { @MainActor in
                        status.phase = .loading
                        overlay.state.phase = .loadingModel
                    }
                },
                onReady: {
                    Task { @MainActor in
                        status.phase = .ready
                        overlay.hide()
                    }
                }
            )
            do {
                try await whisper.warmup()
            } catch {
                await MainActor.run {
                    status.phase = .error(error.localizedDescription)
                    overlay.state.phase = .error("Model load failed: \(error.localizedDescription)")
                }
                Log.info("WhisperLocal: warmup error: \(error)")
            }
        }
    }
}
