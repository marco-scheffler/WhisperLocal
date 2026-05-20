import Foundation

protocol Transcribing: Sendable {
    func ensureLoaded() async throws
    func transcribe(samples: [Float], language: String?) async throws -> String
}
