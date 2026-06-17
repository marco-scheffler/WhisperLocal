import XCTest
@testable import WhisperLocal

final class HallucinationFilterTests: XCTestCase {
    func testTrailingVielenDankAfterContentIsRemoved() {
        let input = "Das ist ein normaler Satz. Vielen Dank."
        XCTAssertEqual(HallucinationFilter.strip(input), "Das ist ein normaler Satz.")
    }

    func testStandaloneVielenDankIsKept() {
        // Whole transcript is "Vielen Dank." — the user likely meant it.
        XCTAssertEqual(HallucinationFilter.strip("Vielen Dank."), "Vielen Dank.")
    }

    func testSubtitleCreditRemovedEvenStandalone() {
        XCTAssertEqual(HallucinationFilter.strip("Untertitel der Amara.org-Community"), "")
    }

    func testSubtitleCreditRemovedAfterContent() {
        let input = "Hallo Welt. Untertitel im Auftrag des ZDF, 2021"
        XCTAssertEqual(HallucinationFilter.strip(input), "Hallo Welt.")
    }

    func testThanksForWatchingRemoved() {
        XCTAssertEqual(HallucinationFilter.strip("Here is my note. Thanks for watching!"), "Here is my note.")
    }

    func testNormalTextUnchanged() {
        let input = "Bitte kauf Milch und Brot."
        XCTAssertEqual(HallucinationFilter.strip(input), input)
    }

    func testMultipleTrailingJunkPeeled() {
        let input = "Der eigentliche Inhalt. Vielen Dank. Thanks for watching!"
        XCTAssertEqual(HallucinationFilter.strip(input), "Der eigentliche Inhalt.")
    }

    func testEmptyInput() {
        XCTAssertEqual(HallucinationFilter.strip(""), "")
        XCTAssertEqual(HallucinationFilter.strip("   "), "")
    }
}

final class AudioTrimmingTests: XCTestCase {
    func testTrailingSilenceIsTrimmed() {
        let sampleRate = 16_000
        // 0.5 s of loud tone followed by 2 s of silence.
        let loud = [Float](repeating: 0.5, count: sampleRate / 2)
        let silence = [Float](repeating: 0.0, count: sampleRate * 2)
        let trimmed = AudioTrimming.trimTrailingSilence(loud + silence, sampleRate: sampleRate)

        // Loud part (8000) + 0.3 s tail (4800) ≈ 12 800, far less than the
        // original 40 000 samples.
        XCTAssertLessThan(trimmed.count, loud.count + silence.count)
        XCTAssertGreaterThanOrEqual(trimmed.count, loud.count)
        XCTAssertLessThanOrEqual(trimmed.count, loud.count + sampleRate / 2)
    }

    func testAllSilenceIsReturnedUnchanged() {
        let silence = [Float](repeating: 0.0, count: 16_000)
        XCTAssertEqual(AudioTrimming.trimTrailingSilence(silence).count, silence.count)
    }

    func testNoTrailingSilenceReturnsUnchanged() {
        let loud = [Float](repeating: 0.4, count: 16_000)
        XCTAssertEqual(AudioTrimming.trimTrailingSilence(loud).count, loud.count)
    }

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(AudioTrimming.trimTrailingSilence([]).isEmpty)
    }
}
