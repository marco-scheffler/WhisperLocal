import SwiftUI

struct PermissionsView: View {
    @State private var status: PermissionStatus = PermissionsManager.current()

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
            row("Input Monitoring (hotkey)", granted: true) {
                PermissionsManager.openInputMonitoringSettings()
            }
        }
        .onAppear { status = PermissionsManager.current() }
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
