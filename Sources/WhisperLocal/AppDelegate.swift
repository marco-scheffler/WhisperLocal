import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let overlay = OverlayWindow()
    private var controller: DictationController?
    private var hotKeys: HotKeyManager?
    private var menuBar: MenuBarController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        let modelStore = ModelStore()
        let whisper = WhisperEngine(modelStore: modelStore)
        let llm = LLMPostProcessor()

        let c = DictationController(
            recorder: recorder,
            transcriber: whisper,
            postProcessor: llm,
            injector: injector,
            overlay: overlay
        )
        c.llmEnabled = Preferences.llmEnabled
        controller = c

        // Forward audio level to overlay state.
        recorder.levelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in self?.overlay.state.level = lvl }
            .store(in: &cancellables)

        let mgr = HotKeyManager(binding: Preferences.hotkey)
        mgr.onPressed  = { Task { @MainActor in await c.handleHotKey(pressed: true) } }
        mgr.onReleased = { Task { @MainActor in await c.handleHotKey(pressed: false) } }
        hotKeys = mgr

        NSLog("WhisperLocal launched")
    }
}
