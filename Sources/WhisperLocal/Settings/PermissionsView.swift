import SwiftUI
import Combine

struct PermissionsView: View {
    @State private var status: PermissionStatus = PermissionsManager.current()
    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Microphone", granted: status.microphone) {
                Task {
                    _ = await PermissionsManager.requestMicrophone()
                    status = PermissionsManager.current()
                }
            }
            row("Accessibility (pasting)", granted: status.accessibility) {
                PermissionsManager.openAccessibilitySettings()
            }
            row("Input Monitoring (hotkey)", granted: status.inputMonitoring) {
                if status.inputMonitoring {
                    PermissionsManager.openInputMonitoringSettings()
                } else {
                    PermissionsManager.requestInputMonitoring()
                }
            }
            if !status.accessibility || !status.microphone || !status.inputMonitoring {
                Text("After granting in System Settings, quit and reopen WhisperLocal for the change to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .onAppear { status = PermissionsManager.current() }
        .onReceive(refreshTimer) { _ in
            status = PermissionsManager.current()
        }
    }

    private func row(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
            Spacer()
            Button(granted ? "Open settings" : "Grant", action: action)
        }
    }
}
