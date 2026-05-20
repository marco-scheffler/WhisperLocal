import Foundation

enum Preferences {
    private static let llmKey = "WhisperLocal.llmEnabled"
    private static let hotkeyKey = "WhisperLocal.hotkey"
    private static let inputDeviceKey = "WhisperLocal.inputDeviceUID"

    static var llmEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: llmKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: llmKey) }
    }

    static var hotkey: HotKeyBinding {
        get {
            guard let dict = UserDefaults.standard.dictionary(forKey: hotkeyKey),
                  let b = HotKeyBinding(dictionary: dict) else { return .default }
            return b
        }
        set { UserDefaults.standard.set(newValue.dictionary, forKey: hotkeyKey) }
    }

    /// nil = follow system default input device.
    static var inputDeviceUID: String? {
        get { UserDefaults.standard.string(forKey: inputDeviceKey) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: inputDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: inputDeviceKey)
            }
        }
    }

    private static let languageKey = "WhisperLocal.language"

    /// nil = auto-detect; otherwise an ISO 639-1 code like "de" or "en".
    static var language: String? {
        get { UserDefaults.standard.string(forKey: languageKey) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: languageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageKey)
            }
        }
    }
}
