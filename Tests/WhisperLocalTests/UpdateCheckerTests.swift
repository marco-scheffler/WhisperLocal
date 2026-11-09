import XCTest
@testable import WhisperLocal

final class UpdateCheckerTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(UpdateChecker.isVersion("0.1.4", newerThan: "0.1.3"))
        XCTAssertTrue(UpdateChecker.isVersion("0.2.0", newerThan: "0.1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("0.1.10", newerThan: "0.1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("v1.0", newerThan: "0.9.9"))
    }

    func testSameOrOlderVersions() {
        XCTAssertFalse(UpdateChecker.isVersion("0.1.3", newerThan: "0.1.3"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2", newerThan: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.1.2", newerThan: "0.1.3"))
        XCTAssertFalse(UpdateChecker.isVersion("0.1.9", newerThan: "0.1.10"))
    }

    func testDecodesGitHubRelease() throws {
        let json = Data("""
        {"tag_name": "v0.1.3", "html_url": "https://github.com/marco-scheffler/WhisperLocal/releases/tag/v0.1.3", "draft": false}
        """.utf8)
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: json)
        XCTAssertEqual(release.tagName, "v0.1.3")
        XCTAssertEqual(release.version, "0.1.3")
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/marco-scheffler/WhisperLocal/releases/tag/v0.1.3")
    }
}
