import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
    private var window: NSWindow?

    var onHotkeyChange: (HotKeyBinding) -> Void = { _ in }
    var onLLMChange: (Bool) -> Void = { _ in }
    var onInputDeviceChange: (String?) -> Void = { _ in }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            onHotkeyChange: { [weak self] in self?.onHotkeyChange($0) },
            onLLMChange: { [weak self] in self?.onLLMChange($0) },
            onInputDeviceChange: { [weak self] in self?.onInputDeviceChange($0) }
        )
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "WhisperLocal Settings"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
