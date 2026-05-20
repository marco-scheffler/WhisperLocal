import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKeys: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        let mgr = HotKeyManager(binding: .default)
        mgr.onPressed = { NSLog("hotkey pressed") }
        mgr.onReleased = { NSLog("hotkey released") }
        hotKeys = mgr

        NSLog("WhisperLocal launched")
    }
}
