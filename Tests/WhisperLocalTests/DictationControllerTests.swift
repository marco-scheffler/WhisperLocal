import XCTest
import Combine
@testable import WhisperLocal

// MARK: - Mock recorder (no hardware, no permissions needed)

final class MockRecorder: Recording, @unchecked Sendable {
    /// Samples returned by `stop()`.
    var stubbedSamples: [Float] = [0.1, 0.2, 0.3]
    /// When non-nil, `start()` throws this error.
    var startError: Error?

    private let levelSubject = PassthroughSubject<Float, Never>()
    var levelPublisher: AnyPublisher<Float, Never> {
        levelSubject.eraseToAnyPublisher()
    }

    func start() throws {
        if let err = startError { throw err }
    }

    func stop() -> [Float] {
        stubbedSamples
    }
}

// MARK: - Mock transcriber

final class MockTranscriber: Transcribing, @unchecked Sendable {
    var output: String = "hallo welt"
    var shouldThrow: Bool = false

    func ensureLoaded() async throws {}

    func transcribe(samples: [Float], language: String?) async throws -> String {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return output
    }
}

// MARK: - Tests

final class DictationControllerTests: XCTestCase {

    // Helper to wait briefly for async pipeline to settle.
    @MainActor
    private func waitForIdle(
        _ controller: DictationController,
        timeout: TimeInterval = 3.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.state != .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000) // 50 ms polls
        }
    }

    // MARK: Happy path: record → transcribe → inject → idle

    @MainActor
    func testHappyPath() async throws {
        let recorder = MockRecorder()
        let transcriber = MockTranscriber()
        transcriber.output = "hallo welt"

        let controller = DictationController(
            recorder: recorder,
            transcriber: transcriber,
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .pushToTalk

        // Start recording
        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)

        // Release key — pipeline runs
        await controller.handleHotKey(pressed: false)

        // Wait for the async sleep inside stopAndProcess + reset
        try await waitForIdle(controller)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Empty transcription → returns to idle without injecting

    @MainActor
    func testEmptyTranscriptionResetsToIdle() async throws {
        let recorder = MockRecorder()
        let transcriber = MockTranscriber()
        transcriber.output = ""   // empty → skip injection

        let controller = DictationController(
            recorder: recorder,
            transcriber: transcriber,
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .pushToTalk

        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)

        await controller.handleHotKey(pressed: false)
        try await waitForIdle(controller)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Mic error → state returns to idle after failure delay

    @MainActor
    func testMicErrorRecovery() async throws {
        let recorder = MockRecorder()
        recorder.startError = NSError(
            domain: "com.test", code: 999,
            userInfo: [NSLocalizedDescriptionKey: "No mic"]
        )
        let controller = DictationController(
            recorder: recorder,
            transcriber: MockTranscriber(),
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .pushToTalk

        await controller.handleHotKey(pressed: true)
        // After mic error the controller goes through fail() which sleeps 1.5 s then resets.
        try await waitForIdle(controller, timeout: 4.0)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Transcription error → state returns to idle

    @MainActor
    func testTranscribeErrorRecovery() async throws {
        let recorder = MockRecorder()
        let transcriber = MockTranscriber()
        transcriber.shouldThrow = true

        let controller = DictationController(
            recorder: recorder,
            transcriber: transcriber,
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .pushToTalk

        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)

        await controller.handleHotKey(pressed: false)
        try await waitForIdle(controller, timeout: 4.0)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Push-to-talk: holding the key past the initial press stays in .recording

    @MainActor
    func testPushToTalkDoublePressIsIgnored() async throws {
        let recorder = MockRecorder()
        let controller = DictationController(
            recorder: recorder,
            transcriber: MockTranscriber(),
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .pushToTalk

        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)

        // Second press while still holding must not change state (PTT semantics).
        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)
    }

    // MARK: Push-to-talk: the duration cap stops a take while the key is still held

    @MainActor
    func testPushToTalkStopsAtMaxDuration() async throws {
        let controller = DictationController(
            recorder: MockRecorder(),
            transcriber: MockTranscriber(),
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .pushToTalk
        controller.maxRecordingSeconds = 0.3

        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)

        // No release — the cap alone must end the take.
        try await waitForIdle(controller, timeout: 4.0)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Toggle: second press stops recording

    @MainActor
    func testToggleSecondPressStops() async throws {
        let recorder = MockRecorder()
        let controller = DictationController(
            recorder: recorder,
            transcriber: MockTranscriber(),
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        controller.recordingMode = .toggle

        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)

        // Second press toggles into the stop/transcribe/inject pipeline.
        await controller.handleHotKey(pressed: true)
        try await waitForIdle(controller, timeout: 4.0)
        XCTAssertEqual(controller.state, .idle)
    }
}
