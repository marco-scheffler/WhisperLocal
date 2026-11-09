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
    private var isCheckingForUpdates = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        apply(state: .idle)
        let menu = NSMenu()
        let title = UpdateChecker.currentVersion.map { "WhisperLocal \($0)" } ?? "WhisperLocal"
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
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

    @objc private func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }
            let result: Result<UpdateChecker.Release, Error>
            do {
                result = .success(try await UpdateChecker.fetchLatestRelease())
            } catch {
                result = .failure(error)
            }
            showUpdateResult(result)
        }
    }

    private func showUpdateResult(_ result: Result<UpdateChecker.Release, Error>) {
        let alert = NSAlert()
        let current = UpdateChecker.currentVersion
        var downloadURL: URL?
        switch result {
        case .failure(let error):
            Log.info("UpdateChecker: lookup failed: \(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.messageText = "Could not check for updates"
            alert.informativeText = error.localizedDescription
        case .success(let release):
            Log.info("UpdateChecker: latest release \(release.tagName), running \(current ?? "unknown")")
            if let current, !UpdateChecker.isVersion(release.version, newerThan: current) {
                alert.messageText = "WhisperLocal is up to date"
                alert.informativeText = "Version \(current) is the latest release."
            } else {
                alert.messageText = "WhisperLocal \(release.version) is available"
                alert.informativeText = current.map { "You have version \($0)." } ?? "The running version is unknown."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                downloadURL = release.htmlURL
            }
        }
        // A menu bar app is not frontmost, so the alert would open behind
        // other windows without this.
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let downloadURL {
            NSWorkspace.shared.open(downloadURL)
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("WhisperLocal.openSettings")
}
