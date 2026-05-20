import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKeys: HotKeyManager?
    private let recorder = AudioRecorder()
    private let overlay = OverlayWindow()
    private let whisper = WhisperEngine(modelStore: ModelStore())
    private let injector = TextInjector()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        // Forward audio level to overlay state.
        recorder.$level
            .receive(on: RunLoop.main)
            .assign(to: \.state.level, on: overlay)
            .store(in: &cancellables)

        let mgr = HotKeyManager(binding: .default)
        mgr.onPressed = { [weak self] in
            guard let self else { return }
            self.overlay.state.phase = .recording
            self.overlay.show()
            do {
                try self.recorder.start()
            } catch {
                self.overlay.state.phase = .error(error.localizedDescription)
            }
        }
        mgr.onReleased = { [weak self] in
            guard let self else { return }
            let samples = self.recorder.stop()
            self.overlay.state.phase = .transcribing
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let text = try await self.whisper.transcribe(samples: samples, language: nil)
                    if !text.isEmpty {
                        self.injector.inject(text)
                    }
                    self.overlay.state.phase = .injecting
                } catch {
                    NSLog("transcribe error: \(error)")
                    self.overlay.state.phase = .error("Transcribe failed")
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.overlay.hide()
            }
        }
        hotKeys = mgr

        NSLog("WhisperLocal launched")
    }
}
