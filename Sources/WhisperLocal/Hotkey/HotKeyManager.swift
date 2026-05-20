import AppKit
import HotKey

/// Manages a single global hotkey binding.
///
/// Two modes are supported, determined by the active `HotKeyBinding`:
/// - **Modifier-only push-to-talk**: `keyCode == 0` with a non-empty modifier set.
///   Uses `NSEvent.addGlobalMonitorForEvents(.flagsChanged)` to detect when the
///   full modifier combo is held or released.
/// - **Normal key combo** (e.g. ⌘⇧Space): registered via the `soffes/HotKey` library.
///
/// All NSEvent monitor callbacks are delivered on the main thread, so this class is
/// annotated `@MainActor` to satisfy Swift 6 strict concurrency.
@MainActor
final class HotKeyManager {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private var hotKey: HotKey?
    private var modifierMonitor: Any?
    private var modifierHeld: Bool = false
    private var binding: HotKeyBinding

    init(binding: HotKeyBinding) {
        self.binding = binding
        apply(binding: binding)
    }

    func update(binding: HotKeyBinding) {
        self.binding = binding
        teardown()
        apply(binding: binding)
    }

    private func apply(binding: HotKeyBinding) {
        if binding.keyCode == 0 && !binding.modifierFlags.isEmpty {
            installModifierOnlyMonitor(flags: binding.modifierFlags)
        } else {
            installKeyHotKey(binding: binding)
        }
    }

    private func installModifierOnlyMonitor(flags: NSEvent.ModifierFlags) {
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let isHeld = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .isSuperset(of: flags)
            if isHeld && !self.modifierHeld {
                self.modifierHeld = true
                self.onPressed?()
            } else if !isHeld && self.modifierHeld {
                self.modifierHeld = false
                self.onReleased?()
            }
        }
    }

    private func installKeyHotKey(binding: HotKeyBinding) {
        guard let key = Key(carbonKeyCode: UInt32(binding.keyCode)) else { return }
        let hk = HotKey(key: key, modifiers: NSEvent.ModifierFlags(rawValue: binding.modifierFlagsRaw))
        hk.keyDownHandler = { [weak self] in self?.onPressed?() }
        hk.keyUpHandler = { [weak self] in self?.onReleased?() }
        hotKey = hk
    }

    private func teardown() {
        hotKey = nil
        if let m = modifierMonitor { NSEvent.removeMonitor(m) }
        modifierMonitor = nil
        modifierHeld = false
    }

    nonisolated func cleanup() {
        // Called from deinit. Properties are nonisolated(unsafe) — safe because
        // the object is being deallocated and no other actor can race us here.
        MainActor.assumeIsolated {
            teardown()
        }
    }

    deinit { cleanup() }
}
