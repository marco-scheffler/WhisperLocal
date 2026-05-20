import XCTest
@testable import WhisperLocal

final class HotKeyBindingTests: XCTestCase {
    func testRoundTrip() {
        let original = HotKeyBinding(keyCode: 49, modifierFlags: [.control, .option])
        let restored = HotKeyBinding(dictionary: original.dictionary)
        XCTAssertEqual(restored, original)
    }

    func testDefault() {
        let def = HotKeyBinding.default
        XCTAssertTrue(def.modifierFlags.contains(.control))
        XCTAssertTrue(def.modifierFlags.contains(.option))
    }
}
