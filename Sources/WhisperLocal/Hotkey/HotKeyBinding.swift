import AppKit

struct HotKeyBinding: Equatable {
    /// `nil` signals modifier-only mode to `HotKeyManager` — no regular key is
    /// required, only the modifier combo. (Not `0`: that is the A key.)
    var keyCode: UInt32?
    var modifierFlagsRaw: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlagsRaw) }
        set { modifierFlagsRaw = newValue.rawValue }
    }

    init(keyCode: UInt32?, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlags.rawValue
    }

    /// Default binding: modifier-only push-to-talk using ⌥⌘ (Option + Command).
    static let `default` = HotKeyBinding(keyCode: nil, modifierFlags: [.option, .command])

    /// Stored under `"key"`, omitted in modifier-only mode. The legacy format
    /// always stored `"keyCode"`, with `0` meaning modifier-only.
    var dictionary: [String: Any] {
        var dict: [String: Any] = ["modifierFlagsRaw": modifierFlagsRaw]
        if let keyCode { dict["key"] = keyCode }
        return dict
    }

    /// Restores a binding from a dictionary (e.g. one read back from UserDefaults).
    /// UserDefaults deserializes plist numbers as their native Swift type, so values
    /// stored as `UInt32`/`UInt` may come back as `Int`. Both forms are accepted.
    init?(dictionary: [String: Any]) {
        guard let m = Self.unsigned(dictionary["modifierFlagsRaw"]) else { return nil }
        self.modifierFlagsRaw = m
        if let key = Self.unsigned(dictionary["key"]).flatMap(UInt32.init(exactly:)) {
            self.keyCode = key
        } else if let legacy = Self.unsigned(dictionary["keyCode"]).flatMap(UInt32.init(exactly:)) {
            self.keyCode = legacy == 0 ? nil : legacy
        } else {
            self.keyCode = nil
        }
    }

    private static func unsigned(_ value: Any?) -> UInt? {
        switch value {
        case let v as UInt: return v
        case let v as UInt32: return UInt(v)
        case let v as Int where v >= 0: return UInt(v)
        default: return nil
        }
    }
}
