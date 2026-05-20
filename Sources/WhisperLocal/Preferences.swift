import Foundation

enum Preferences {
    private static let llmKey = "WhisperLocal.llmEnabled"
    private static let hotkeyKey = "WhisperLocal.hotkey"

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
}
