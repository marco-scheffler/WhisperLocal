import XCTest
import AppKit
@testable import WhisperLocal

final class PasteboardSnapshotTests: XCTestCase {
    func testSnapshotAndRestoreString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("WhisperLocalTest"))
        pb.clearContents()
        pb.setString("original", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pb)
        pb.clearContents()
        pb.setString("replaced", forType: .string)
        XCTAssertEqual(pb.string(forType: .string), "replaced")

        snapshot.restore(to: pb)
        XCTAssertEqual(pb.string(forType: .string), "original")
    }
}
