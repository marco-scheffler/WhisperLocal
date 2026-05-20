import Foundation

struct ModelStore {
    let bundleId: String
    private static let legacyBundleId = "com.weber.WhisperLocal"

    init(bundleId: String = "io.github.weber-marcoscheffler.WhisperLocal") {
        self.bundleId = bundleId
        Self.migrateIfNeeded(to: bundleId)
    }

    var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent(bundleId).appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var whisperModelDirectory: URL {
        let url = baseDirectory.appendingPathComponent("whisper")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var llmModelDirectory: URL {
        let url = baseDirectory.appendingPathComponent("llm")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One-time migration so users who installed under the pre-public bundle
    /// id don't re-download the ~600 MB Whisper model.
    private static func migrateIfNeeded(to newBundleId: String) {
        guard newBundleId != legacyBundleId else { return }
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldRoot = appSupport.appendingPathComponent(legacyBundleId)
        let newRoot = appSupport.appendingPathComponent(newBundleId)
        guard fm.fileExists(atPath: oldRoot.path),
              !fm.fileExists(atPath: newRoot.path)
        else { return }
        do {
            try fm.moveItem(at: oldRoot, to: newRoot)
        } catch {
            // Non-fatal — model will simply re-download.
        }
    }
}
