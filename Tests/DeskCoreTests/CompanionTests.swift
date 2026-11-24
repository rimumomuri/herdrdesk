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
        XCTAssertNil(CompanionLayout.pageState(["mood": "working", "face": ["provider": "<script>"]])?["face"] as? [String: Any])
        XCTAssertNil(CompanionLayout.pageState(["mood": "working", "face": ["provider": "codex", "style": "\"><img>"]])?["face"] as? [String: Any])
        XCTAssertNil(CompanionLayout.pageState(["mood": "working"])?["face"] as? [String: Any])
    }
}
