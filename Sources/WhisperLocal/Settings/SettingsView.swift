import SwiftUI

struct SettingsView: View {
    @State private var hotkey: HotKeyBinding = Preferences.hotkey
    @State private var llmEnabled: Bool = Preferences.llmEnabled

    var onHotkeyChange: (HotKeyBinding) -> Void
    var onLLMChange: (Bool) -> Void

    var body: some View {
        Form {
            Section("Hotkey") {
                HotKeyCaptureView(binding: $hotkey)
                    .frame(height: 36)
                Button("Reset to default") {
                    hotkey = .default
                }
            }
            Section("Post-processing") {
                Toggle("Clean transcript with local LLM", isOn: $llmEnabled)
            }
            Section("Permissions") {
                PermissionsView()
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420, height: 380)
        .onChange(of: hotkey) { _, new in
            Preferences.hotkey = new
            onHotkeyChange(new)
        }
        .onChange(of: llmEnabled) { _, new in
            Preferences.llmEnabled = new
            onLLMChange(new)
        }
    }
}
