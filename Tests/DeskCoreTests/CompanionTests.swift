import Foundation
import XCTest
@testable import DeskCore

final class CompanionTests: XCTestCase {
    func show(_ mood: String, enabled: Bool = true, attentionOnly: Bool = false, active: Bool = false, snoozed: Bool = false, idleFor: TimeInterval? = nil) -> Bool {
        CompanionLayout.visible(mood: mood, enabled: enabled, attentionOnly: attentionOnly, appActive: active, snoozed: snoozed, idleFor: idleFor)
    }

    func testShownOnlyWhileHerdrDeskIsInTheBackgroundAndTurnedOnAndNotSnoozed() {
        XCTAssertTrue(show("working"))
        XCTAssertFalse(show("working", active: true))
        XCTAssertFalse(show("attention", enabled: false))
        XCTAssertFalse(show("attention", snoozed: true))
    }

    func testIdleSheepFallsAsleepThenLeavesAfterTheGracePeriod() {
        XCTAssertTrue(show("idle", idleFor: 3))
        XCTAssertFalse(show("idle", idleFor: CompanionLayout.idleGrace + 1))
        XCTAssertFalse(show("idle"), "idle from the start is never shown")
    }

    func testAttentionOnlyModeHidesEverythingElse() {
        XCTAssertTrue(show("attention", attentionOnly: true))
        for mood in ["working", "offline", "idle"] { XCTAssertFalse(show(mood, attentionOnly: true, idleFor: 1), mood) }
        XCTAssertTrue(show("offline"))
    }

    func testUnknownMoodIsNeverShown() {
        XCTAssertFalse(show("approve"))
    }

    func testSavedPlaceIsKeptOnlyWhileItFitsOnAScreen() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875), side = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        XCTAssertEqual(CompanionLayout.origin(saved: CGPoint(x: 1500, y: 100), screens: [main, side]), CGPoint(x: 1500, y: 100))
        let fallback = CGPoint(x: main.maxX - CompanionLayout.inset - CompanionLayout.side, y: main.maxY - CompanionLayout.inset - CompanionLayout.side)
        XCTAssertEqual(CompanionLayout.origin(saved: CGPoint(x: 5000, y: 100), screens: [main, side]), fallback)
        XCTAssertEqual(CompanionLayout.origin(saved: CGPoint(x: 1400, y: 100), screens: [main]), fallback, "half off the edge")
        XCTAssertEqual(CompanionLayout.origin(saved: nil, screens: [main]), fallback)
    }

    func testPageStateKeepsOnlyKnownFieldsAndShortLines() {
        let long = String(repeating: "가", count: 300)
        let state = CompanionLayout.pageState(["mood": "attention", "count": 2, "working": 1, "flash": "done", "lines": [long, 7, "b", "c", "d", "e"],
                                               "extra": "x", "menu": ["snooze": "숨기기"]])
        XCTAssertEqual(state?["mood"] as? String, "attention")
        XCTAssertEqual(state?["count"] as? Int, 2)
        XCTAssertEqual((state?["lines"] as? [String])?.count, 4)
        XCTAssertEqual((state?["lines"] as? [String])?.first?.count, 120)
        XCTAssertNil(state?["extra"])
        XCTAssertNil(state?["menu"])
        XCTAssertNil(CompanionLayout.pageState(["mood": "run-script"]))
        XCTAssertNil(CompanionLayout.pageState(["mood": "working", "flash": "boom"])?["flash"] as? String)
        XCTAssertEqual(CompanionLayout.pageState(["mood": "idle", "flash": "done", "flashAt": 1764000000123.0])?["flashAt"] as? Double, 1764000000123)
        XCTAssertNil(CompanionLayout.pageState(["mood": "idle", "flash": "done", "flashAt": "soon"])?["flashAt"] as? Double)
    }

    func testHoverBubbleOpensLeftUnlessThatLeavesTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let right = CompanionLayout.expanded(sheep: CGRect(x: 1300, y: 700, width: 84, height: 84), screens: [screen])
        XCTAssertEqual(right.frame, CGRect(x: 1384 - CompanionLayout.wide, y: 700, width: CompanionLayout.wide, height: 84))
        XCTAssertFalse(right.bubbleRight)
        let left = CompanionLayout.expanded(sheep: CGRect(x: 30, y: 700, width: 84, height: 84), screens: [screen])
        XCTAssertEqual(left.frame, CGRect(x: 30, y: 700, width: CompanionLayout.wide, height: 84))
        XCTAssertTrue(left.bubbleRight)
    }

    func testFaceKeepsOnlyKnownLookFields() {
        let face = CompanionLayout.pageState(["mood": "working", "face": ["provider": "codex", "style": "lamb", "coat": "cocoa", "accessory": "crown",
                                                                         "sleeping": false, "working": true, "name": "킁킁 총괄"]])?["face"] as? [String: Any]
        XCTAssertEqual(face?["provider"] as? String, "codex")
        XCTAssertEqual(face?["style"] as? String, "lamb")
        XCTAssertEqual(face?["working"] as? Bool, true)
        XCTAssertNil(face?["name"])
        XCTAssertEqual(face?["kind"] as? String, "lead")
        let lead = CompanionLayout.pageState(["mood": "working", "face": ["provider": "codex", "kind": "agent",
            "mouth": ["codex", "claude", "<b>", 3, "codex", "codex", "codex", "codex", "codex", "codex", "codex", "codex"]]])?["face"] as? [String: Any]
        XCTAssertEqual(lead?["kind"] as? String, "agent")
        XCTAssertEqual(lead?["mouth"] as? [String], ["codex", "claude", "codex", "codex", "codex", "codex", "codex"])   // first nine, known engines only
        XCTAssertNil(CompanionLayout.pageState(["mood": "working", "face": ["provider": "<script>"]])?["face"] as? [String: Any])
        XCTAssertNil(CompanionLayout.pageState(["mood": "working", "face": ["provider": "codex", "style": "\"><img>"]])?["face"] as? [String: Any])
        XCTAssertNil(CompanionLayout.pageState(["mood": "working"])?["face"] as? [String: Any])
    }

    func testUsageLimitIsAMoodShownUnlessOnlyAttentionIsWanted() {
        XCTAssertEqual(CompanionLayout.pageState(["mood": "limit", "limited": 2])?["limited"] as? Int, 2)
        XCTAssertTrue(show("limit"))
        XCTAssertFalse(show("limit", attentionOnly: true))
    }
}

final class CompanionStatsTests: XCTestCase {
    func testOnlyKnownSectionsWithShortTextReachThePage() {
        let long = String(repeating: "가", count: 200)
        let stats: [[String: Any]] = [
            ["kind": "working", "title": "진행 중", "count": 6, "more": "+2", "rows": [["name": "킁킁맵 총괄", "meta": "12분 3초"], ["name": long, "meta": long], 7]],
            ["kind": "script", "title": "x", "rows": []],
            ["kind": "done", "title": "완료", "count": 1, "rows": [["name": "라인챗봇", "meta": "방금"]]],
        ]
        let page = CompanionLayout.pageState(["mood": "working", "stats": stats])?["stats"] as? [[String: Any]] ?? []
        XCTAssertEqual(page.map { $0["kind"] as? String }, ["working", "done"])
        let rows = page[0]["rows"] as? [[String: String]] ?? []
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["name": "킁킁맵 총괄", "meta": "12분 3초"])
        XCTAssertEqual(rows[1]["name"]?.count, 60)
        XCTAssertEqual(page[0]["count"] as? Int, 6)
    }

    func testThePanelIsTallEnoughForItsRows() {
        XCTAssertEqual(CompanionLayout.panelHeight(sections: []), CompanionLayout.side)
        let one = CompanionLayout.panelHeight(sections: [3])
        let two = CompanionLayout.panelHeight(sections: [3, 1])
        XCTAssertGreaterThan(one, CompanionLayout.side - 1)
        XCTAssertGreaterThan(two, one)
    }

    func testATallPanelOpensDownwardNearTheTopOfTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let top = CompanionLayout.expanded(sheep: CGRect(x: 1300, y: 767, width: 84, height: 84), screens: [screen], height: 220)
        XCTAssertEqual(top.frame.maxY, 851)          // the sheep's top stays put, the panel grows down
        XCTAssertTrue(top.down)
        let low = CompanionLayout.expanded(sheep: CGRect(x: 1300, y: 100, width: 84, height: 84), screens: [screen], height: 220)
        XCTAssertEqual(low.frame.minY, 100)          // grows up
        XCTAssertFalse(low.down)
    }
}

final class CompanionFitTests: XCTestCase {
    func testAPanelTallerThanEitherSideStaysOnScreenOnTheRoomierSide() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 640)
        let open = CompanionLayout.expanded(sheep: CGRect(x: 1300, y: 280, width: 84, height: 84), screens: [screen], height: 500)
        XCTAssertGreaterThanOrEqual(open.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(open.frame.maxY, screen.maxY)
        XCTAssertTrue(open.down)                           // 360 points above the sheep's bottom, 364 below its top: down wins
        XCTAssertEqual(open.frame.maxY, 364)
        XCTAssertEqual(open.frame.height, 364)
    }

    func testOfflineAndLimitLinesAddToThePanelHeight() {
        XCTAssertGreaterThan(CompanionLayout.panelHeight(sections: [1], lines: 2), CompanionLayout.panelHeight(sections: [1]))
    }
}

final class CompanionBubbleWindowTests: XCTestCase {
    func testThePanelWindowSitsBesideTheSheepWithoutCoveringIt() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let sheep = CGRect(x: 1300, y: 100, width: 84, height: 84)
        let left = CompanionLayout.bubbleFrame(sheep: sheep, screens: [screen], height: 200)
        XCTAssertEqual(left.frame.maxX, sheep.minX)
        XCTAssertEqual(left.frame.width, CompanionLayout.wide - CompanionLayout.side)
        XCTAssertEqual(left.frame.minY, 100)                 // grows up from the sheep's bottom
        XCTAssertEqual(left.frame.height, 200)
        XCTAssertFalse(left.right); XCTAssertFalse(left.down)
        let edge = CompanionLayout.bubbleFrame(sheep: CGRect(x: 20, y: 767, width: 84, height: 84), screens: [screen], height: 200)
        XCTAssertEqual(edge.frame.minX, 104)                 // opens to the right of a sheep at the left edge
        XCTAssertEqual(edge.frame.maxY, 851)                 // and down from a sheep at the top
        XCTAssertTrue(edge.right); XCTAssertTrue(edge.down)
    }
}

final class CompanionDragTests: XCTestCase {
    func testASmallWiggleIsAClickNotADrag() {
        var drag = CompanionDrag()
        drag.press(at: CGPoint(x: 10, y: 10), origin: CGPoint(x: 100, y: 100))
        XCTAssertNil(drag.move(to: CGPoint(x: 12, y: 11)).origin)
        XCTAssertEqual(drag.release(), .click)
    }

    func testDraggingStartsOnceThenFollowsTheMouseWithoutAJump() {
        var drag = CompanionDrag()
        drag.press(at: CGPoint(x: 10, y: 10), origin: CGPoint(x: 100, y: 100))
        let first = drag.move(to: CGPoint(x: 20, y: 10))
        XCTAssertTrue(first.began)
        XCTAssertEqual(first.origin, CGPoint(x: 110, y: 100))
        // the window shrank when the drag began (bubble closed): the whole movement so far still counts, from its new origin
        drag.rebase(origin: CGPoint(x: 316, y: 100))
        XCTAssertEqual(drag.move(to: CGPoint(x: 20, y: 10)).origin, CGPoint(x: 326, y: 100))
        let second = drag.move(to: CGPoint(x: 30, y: 15))
        XCTAssertFalse(second.began)
        XCTAssertEqual(second.origin, CGPoint(x: 336, y: 105))
        XCTAssertEqual(drag.release(), .moved)
    }

    func testHoverChangesAreIgnoredWhileTheButtonIsDown() {
        var drag = CompanionDrag()
        XCTAssertTrue(drag.acceptsHover)
        drag.press(at: .zero, origin: .zero)
        XCTAssertFalse(drag.acceptsHover)
        _ = drag.move(to: CGPoint(x: 50, y: 0))
        XCTAssertFalse(drag.acceptsHover)
        _ = drag.release()
        XCTAssertTrue(drag.acceptsHover)
    }
}
