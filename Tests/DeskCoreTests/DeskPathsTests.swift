import XCTest
@testable import DeskCore

final class DeskPathsTests: XCTestCase {
    func testPublicBuildKeepsItsDataInAFolderNamedAfterTheAppID() {
        guard ProcessInfo.processInfo.environment["HERDRDESK_DATA"] == nil else { return }
        XCTAssertFalse(DeskPaths.retainsLegacyProfile)
        XCTAssertTrue(DeskPaths.data.path.hasSuffix("Library/Application Support/app.herdrdesk"), DeskPaths.data.path)
    }
}
