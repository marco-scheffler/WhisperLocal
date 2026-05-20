import AppKit

@MainActor
final class MenuBarController: NSObject {
    enum IconState {
        case idle
        case downloading
        case recording
        case working   // transcribing / post-processing
    }

    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        apply(state: .idle)
        let menu = NSMenu()
        menu.addItem(withTitle: "WhisperLocal", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func apply(state: IconState) {
        guard let button = statusItem.button else { return }
        let (symbol, tint): (String, NSColor?) = {
            switch state {
            case .idle:        return ("mic", nil)
            case .downloading: return ("arrow.down.circle", .systemBlue)
            case .recording:   return ("mic.fill", .systemRed)
            case .working:     return ("waveform", .systemBlue)
            }
        }()
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "WhisperLocal")?
            .withSymbolConfiguration(config)
        image?.isTemplate = (tint == nil)
        button.image = image
        button.contentTintColor = tint
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("WhisperLocal.openSettings")
}
