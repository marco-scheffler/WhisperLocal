import SwiftUI

struct SettingsView: View {
    @State private var hotkey: HotKeyBinding = Preferences.hotkey
    @State private var llmEnabled: Bool = Preferences.llmEnabled
    @State private var language: String = Preferences.language ?? ""
    @State private var recordingMode: RecordingMode = Preferences.recordingMode
    @ObservedObject var modelStatus: ModelStatus = AppDelegate.modelStatus

    var onHotkeyChange: (HotKeyBinding) -> Void
    var onLLMChange: (Bool) -> Void
    var onInputDeviceChange: (String?) -> Void
    var onRecordingModeChange: (RecordingMode) -> Void

    var body: some View {
        Form {
            Section("Whisper model") {
                HStack(spacing: 10) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelStatus.modelName.isEmpty ? "—" : modelStatus.modelName)
                            .font(.system(.body, design: .monospaced))
                        Text(modelStatus.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .downloading(let p) = modelStatus.phase {
                        ProgressView(value: p)
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                    }
                }
            }
            Section("Microphone") {
                AudioDevicePicker(initial: Preferences.inputDeviceUID) { uid in
                    Preferences.inputDeviceUID = uid
                    onInputDeviceChange(uid)
                }
            }
            Section("Language") {
                Picker("", selection: $language) {
                    Text("Auto-detect").tag("")
                    Text("German (Deutsch)").tag("de")
                    Text("English").tag("en")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Section("Hotkey") {
                HotKeyCaptureView(binding: $hotkey)
                    .frame(height: 36)
                Button("Reset to default") {
                    hotkey = .default
                }
                Picker("Mode", selection: $recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
            Section("Post-processing") {
                Toggle("Clean transcript with local LLM", isOn: $llmEnabled)
            }
            Section("Permissions") {
                PermissionsView()
            }
            Section("Logs") {
                LogView()
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540, height: 720)
        .onChange(of: hotkey) { _, new in
            Preferences.hotkey = new
            onHotkeyChange(new)
        }
        .onChange(of: llmEnabled) { _, new in
            Preferences.llmEnabled = new
            onLLMChange(new)
        }
        .onChange(of: language) { _, new in
            Preferences.language = new.isEmpty ? nil : new
        }
        .onChange(of: recordingMode) { _, new in
            Preferences.recordingMode = new
            onRecordingModeChange(new)
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch modelStatus.phase {
        case .idle:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .loading:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
