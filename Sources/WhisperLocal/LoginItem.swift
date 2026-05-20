import Foundation
import ServiceManagement

/// Manages whether the app launches automatically at user login via
/// `SMAppService.mainApp`. macOS 13+.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    Log.info("LoginItem: registered for auto-launch")
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                    Log.info("LoginItem: unregistered from auto-launch")
                }
            }
        } catch {
            Log.error("LoginItem: failed to toggle (\(error.localizedDescription))")
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:       return "Enabled"
        case .notRegistered: return "Not enabled"
        case .notFound:      return "Not registered with system"
        case .requiresApproval:
            return "Awaiting approval in System Settings → General → Login Items"
        @unknown default:    return "Unknown"
        }
    }
}
