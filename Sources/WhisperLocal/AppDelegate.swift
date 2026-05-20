import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKeys: HotKeyManager?
    private let recorder = AudioRecorder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        let mgr = HotKeyManager(binding: .default)
        mgr.onPressed = { [weak self] in
            guard let self else { return }
            do {
                try self.recorder.start()
                NSLog("recording…")
            } catch {
                NSLog("recorder error: \(error)")
            }
        }
        mgr.onReleased = { [weak self] in
            guard let self else { return }
            let s = self.recorder.stop()
            NSLog("captured \(s.count) samples @ 16kHz (\(Double(s.count) / 16_000.0)s)")
        }
        hotKeys = mgr

        NSLog("WhisperLocal launched")
    }
}
