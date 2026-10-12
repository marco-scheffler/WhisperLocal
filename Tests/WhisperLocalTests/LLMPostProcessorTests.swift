import XCTest
@testable import WhisperLocal

final class LLMPostProcessorTests: XCTestCase {
    func testTimeoutReturnsFallbackWhenOperationIgnoresCancellation() async {
        let started = Date()
        let result = await LLMPostProcessor.withTimeout(seconds: 0.1, fallback: "fallback") {
            // A continuation resumed from GCD does not react to task cancellation.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    continuation.resume(returning: "slow")
                }
            }
        }
        XCTAssertEqual(result, "fallback")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testFastOperationWins() async {
        let result = await LLMPostProcessor.withTimeout(seconds: 2, fallback: "fallback") { "fast" }
        XCTAssertEqual(result, "fast")
    }
}
