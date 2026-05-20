import AppKit

struct HotKeyBinding: Equatable, Codable {
    var keyCode: UInt32
    var modifierFlagsRaw: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlagsRaw) }
        set { modifierFlagsRaw = newValue.rawValue }
    }

    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlags.rawValue
    }

    /// Default binding: modifier-only push-to-talk using ⌥⌘ (Option + Command).
    /// `keyCode == 0` with non-empty `modifierFlags` signals modifier-only mode to
    /// `HotKeyManager` — no regular key is required, only the modifier combo.
    static let `default` = HotKeyBinding(keyCode: 0, modifierFlags: [.option, .command])

    var dictionary: [String: Any] {
        ["keyCode": keyCode, "modifierFlagsRaw": modifierFlagsRaw]
    }

    /// Restores a binding from a dictionary (e.g. one read back from UserDefaults).
    /// UserDefaults deserializes plist numbers as their native Swift type, so values
    /// stored as `UInt32`/`UInt` may come back as `Int`. Both forms are accepted.
    init?(dictionary: [String: Any]) {
        if let k = dictionary["keyCode"] as? UInt32,
           let m = dictionary["modifierFlagsRaw"] as? UInt {
            self.keyCode = k
            self.modifierFlagsRaw = m
            return
        }
        if let k = dictionary["keyCode"] as? Int,
           let m = dictionary["modifierFlagsRaw"] as? Int {
            self.keyCode = UInt32(k)
            self.modifierFlagsRaw = UInt(m)
            return
        }
        return nil
    }
}
