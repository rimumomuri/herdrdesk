import XCTest
@testable import DeskCore

final class PushDiffTests: XCTestCase {
    func testUnchangedLargePartsAreLeftOutAndSmallOnesAlwaysGo() {
        var diff = PushDiff()
        let first = diff.trim(["terms": [1], "replies": [["id": "a"]], "connection": "live"])
        XCTAssertNotNil(first["replies"])
        let second = diff.trim(["terms": [1], "replies": [["id": "a"]], "connection": "live"])
        XCTAssertNil(second["replies"], "unchanged: the page keeps what it has")
        XCTAssertNotNil(second["terms"], "terminals always go")
        XCTAssertEqual(second["connection"] as? String, "live")
        let third = diff.trim(["terms": [1], "replies": [["id": "a"], ["id": "b"]]])
        XCTAssertEqual((third["replies"] as? [[String: String]])?.count, 2, "changed: sent again")
    }

    func testAFreshPageGetsEverythingAgain() {
        var diff = PushDiff()
        _ = diff.trim(["replies": [["id": "a"]]])
        diff.reset()
        XCTAssertNotNil(diff.trim(["replies": [["id": "a"]]])["replies"])
    }

    func testKeyOrderDoesNotCountAsAChange() {
        var diff = PushDiff()
        _ = diff.trim(["ledger": ["q1": "sent", "q2": "open"]])
        XCTAssertNil(diff.trim(["ledger": ["q2": "open", "q1": "sent"]])["ledger"])
    }
}
