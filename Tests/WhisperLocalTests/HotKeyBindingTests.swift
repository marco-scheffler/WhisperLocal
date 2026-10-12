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
        XCTAssertNil(def.keyCode)
        XCTAssertTrue(def.modifierFlags.contains(.option))
        XCTAssertTrue(def.modifierFlags.contains(.command))
    }

    // Key code 0 is the A key, not "no key".
    func testAKeyRoundTrip() {
        let original = HotKeyBinding(keyCode: 0, modifierFlags: [.option, .command])
        let restored = HotKeyBinding(dictionary: original.dictionary)
        XCTAssertEqual(restored?.keyCode, 0)
    }

    func testModifierOnlyRoundTrip() {
        let restored = HotKeyBinding(dictionary: HotKeyBinding.default.dictionary)
        XCTAssertEqual(restored, .default)
    }

    func testLegacyZeroKeyCodeMeansModifierOnly() {
        let legacy: [String: Any] = ["keyCode": 0, "modifierFlagsRaw": Int(HotKeyBinding.default.modifierFlagsRaw)]
        XCTAssertEqual(HotKeyBinding(dictionary: legacy), .default)
    }

    func testLegacyKeyCodeIsKept() {
        let legacy: [String: Any] = ["keyCode": 49, "modifierFlagsRaw": 0]
        XCTAssertEqual(HotKeyBinding(dictionary: legacy)?.keyCode, 49)
    }
}
