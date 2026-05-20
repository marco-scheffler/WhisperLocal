import Foundation

/// Protocol for text post-processing (e.g. LLM-based cleanup).
/// The concrete implementation is provided in Task 10.
protocol TextCleaning: Sendable {
    func clean(text: String) async throws -> String
}
