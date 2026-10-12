import Foundation
import Synchronization

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Protocol for text post-processing (e.g. LLM-based cleanup).
protocol TextCleaning: Sendable {
    func clean(text: String) async throws -> String
}

actor LLMPostProcessor: TextCleaning {
    private let timeoutSeconds: Double

    init(timeoutSeconds: Double = 3.0) {
        self.timeoutSeconds = timeoutSeconds
    }

    func clean(text: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return await runOnSystemModel(text: text)
            default:
                return text
            }
        }
        return text
#else
        return text
#endif
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func runOnSystemModel(text: String) async -> String {
        let instructions = """
        You receive a raw speech-to-text transcript. Output the same content, but corrected for \
        grammar, punctuation, and capitalization. Remove filler words (uh, um, ähm, äh, also). Do not add new \
        content. Do not translate. Detect the input language (German or English) and stay in it. Output the \
        cleaned text only, no preface, no quotes, no preamble like "Here is the cleaned text:".
        """
        let session = LanguageModelSession(instructions: instructions)
        let cleaned = await Self.withTimeout(seconds: timeoutSeconds, fallback: text) {
            do {
                let response = try await session.respond(to: text)
                let value = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? text : value
            } catch {
                return text
            }
        }
        return cleaned
    }
#endif

    /// Returns `op`'s result, or `fallback` once `seconds` have passed. Unlike a
    /// task group — which waits for every child before returning — this returns
    /// on time even if `op` ignores cancellation; `op` is cancelled and left to
    /// finish in the background.
    static func withTimeout<T: Sendable>(
        seconds: Double,
        fallback: T,
        _ op: @escaping @Sendable () async -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            let first = FirstResult(continuation)
            let work = Task { first.resume(await op()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                work.cancel()
                first.resume(fallback)
            }
        }
    }
}

/// Resumes a continuation with whichever value arrives first and ignores the rest.
private final class FirstResult<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, Never>?>

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ value: T) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }
}
