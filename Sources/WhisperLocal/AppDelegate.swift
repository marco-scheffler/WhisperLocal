import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKeys: HotKeyManager?
    private let recorder = AudioRecorder()
    private let overlay = OverlayWindow()
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
            _ = self.recorder.stop()
            self.overlay.state.phase = .injecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.overlay.hide()
            }
        }
        hotKeys = mgr

        NSLog("WhisperLocal launched")
    }
}
