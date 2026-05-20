import Foundation

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

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        fallback: T,
        _ op: @escaping @Sendable () async -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return fallback
            }
            let first = await group.next() ?? fallback
            group.cancelAll()
            return first
        }
    }
}
