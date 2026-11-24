import XCTest
@testable import DeskCore

final class LiveTurnRuleTests: XCTestCase {
    func testAFinishCountsOnlyForTheTurnThatWasSeenStarting() {
        let started = ["state":"working","turn":"A"]
        XCTAssertTrue(LiveTurnRule.accepts(previous: nil, entry: started))
        XCTAssertTrue(LiveTurnRule.accepts(previous: started, entry: ["state":"done","turn":"A"]))
        XCTAssertFalse(LiveTurnRule.accepts(previous: started, entry: ["state":"done","turn":"B"]), "another turn's finish")
    }

    func testAfterARestartAFinishWithoutItsStartIsIgnored() {
        XCTAssertFalse(LiveTurnRule.accepts(previous: nil, entry: ["state":"done","turn":"A"]))
        XCTAssertFalse(LiveTurnRule.accepts(previous: ["state":"working","turn":"A"], entry: ["state":"done"]))
    }
}
