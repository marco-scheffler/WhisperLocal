import Foundation

struct ModelStore {
    let bundleId: String

    init(bundleId: String = "io.github.marco-scheffler.WhisperLocal") {
        self.bundleId = bundleId
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
}
