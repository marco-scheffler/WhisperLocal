import XCTest
import ObjCExceptionCatcher
@testable import WhisperLocal

/// AVFAudio raises Objective-C exceptions for fatal misconfiguration — most
/// notably `installTapOnBus:` with a format the input hardware does not have.
/// Those cannot be caught with Swift `try`, and an uncaught one tears the app
/// down without writing a crash report. These tests cover the shim that turns
/// them into ordinary Swift errors.
final class ObjCExceptionTests: XCTestCase {
    func testNonThrowingBlockRunsToCompletion() throws {
        var ran = false
        try ObjCException.catching { ran = true }
        XCTAssertTrue(ran)
    }

    func testRaisedExceptionBecomesSwiftError() {
        XCTAssertThrowsError(
            try ObjCException.catching {
                NSException(
                    name: .invalidArgumentException,
                    reason: "required condition is false: format.sampleRate == hwFormat.sampleRate",
                    userInfo: nil
                ).raise()
            }
        ) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, WLObjCExceptionErrorDomain)
            XCTAssertEqual(
                nsError.localizedDescription,
                "required condition is false: format.sampleRate == hwFormat.sampleRate"
            )
            XCTAssertEqual(
                nsError.userInfo[WLObjCExceptionNameKey] as? String,
                NSExceptionName.invalidArgumentException.rawValue
            )
        }
    }

    func testExceptionWithoutReasonStillReportsAName() {
        XCTAssertThrowsError(
            try ObjCException.catching {
                NSException(name: .genericException, reason: nil, userInfo: nil).raise()
            }
        ) { error in
            XCTAssertFalse((error as NSError).localizedDescription.isEmpty)
        }
    }

    func testControlFlowResumesAfterACaughtException() throws {
        // The whole point of the shim: the process survives and the caller can
        // report the failure instead of disappearing.
        var recovered = false
        do {
            try ObjCException.catching {
                NSException(name: .genericException, reason: "boom", userInfo: nil).raise()
            }
        } catch {
            recovered = true
        }
        XCTAssertTrue(recovered)

        var ran = false
        try ObjCException.catching { ran = true }
        XCTAssertTrue(ran)
    }
}
