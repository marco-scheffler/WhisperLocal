import XCTest
@testable import WhisperLocal

final class ModelStoreTests: XCTestCase {
    func testWhisperPath() {
        let store = ModelStore(bundleId: "com.test.app")
        XCTAssertTrue(store.whisperModelDirectory.path.contains("Application Support/com.test.app/Models/whisper"))
    }

    func testLLMPath() {
        let store = ModelStore(bundleId: "com.test.app")
        XCTAssertTrue(store.llmModelDirectory.path.contains("Application Support/com.test.app/Models/llm"))
    }
}
