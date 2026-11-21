import XCTest
@testable import DeskCore

final class MachineSettingsTests: XCTestCase {
    func testSetBuildsOnlyTheFieldsGiven() {
        XCTAssertEqual(MachineSettings.argv(["action": "set", "name": "laptop", "ready": "off", "slots": 3], terms: []),
                       ["machine", "set", "laptop", "--ready", "off", "--slots", "3"])
        XCTAssertEqual(MachineSettings.argv(["action": "set", "name": "laptop", "tier": "light"], terms: []),
                       ["machine", "set", "laptop", "--tier", "light"])
    }

    func testSetRefusesBadValues() {
        XCTAssertNil(MachineSettings.argv(["action": "set", "name": "laptop", "ready": "maybe"], terms: []))
        XCTAssertNil(MachineSettings.argv(["action": "set", "name": "laptop", "slots": -1], terms: []))
        XCTAssertNil(MachineSettings.argv(["action": "set", "name": "--evil", "ready": "on"], terms: []))
        XCTAssertNil(MachineSettings.argv(["action": "set", "name": "laptop"], terms: []))
    }

    func testSuggestAsksHerdrTaskForTheTeamsStudioRepo() {
        XCTAssertEqual(MachineSettings.argv(["action": "suggest", "team": "shop"], terms: []), ["machine", "suggest", "--team", "shop"])
        XCTAssertNil(MachineSettings.argv(["action": "suggest", "team": "../x"], terms: []))
    }

    func testCloneNeedsATeamAUrlAndAPath() {
        let body: [String: Any] = ["action": "clone", "name": "laptop", "team": "shop",
                                   "url": "https://github.com/o/shop.git", "path": "~/work/shop"]
        XCTAssertEqual(MachineSettings.argv(body, terms: []),
                       ["machine", "clone", "laptop", "--team", "shop", "--url", "https://github.com/o/shop.git", "--path", "~/work/shop"])
        var bad = body; bad["url"] = "-oProxyCommand=x"
        XCTAssertNil(MachineSettings.argv(bad, terms: []))
        bad = body; bad["path"] = "work/shop"
        XCTAssertNil(MachineSettings.argv(bad, terms: []))
        bad = body; bad["path"] = "~/a\nb"
        XCTAssertNil(MachineSettings.argv(bad, terms: []))
        bad = body; bad["url"] = "https://x y"
        XCTAssertNil(MachineSettings.argv(bad, terms: []))
    }

    func testUnlinkAndUnknownActions() {
        XCTAssertEqual(MachineSettings.argv(["action": "unlink", "name": "laptop", "team": "shop"], terms: []),
                       ["machine", "unlink", "laptop", "--team", "shop"])
        XCTAssertNil(MachineSettings.argv(["action": "rm", "name": "laptop"], terms: []))
    }

    func testCloneGetsALongTimeoutAndEverythingElseAShortOne() {
        XCTAssertGreaterThanOrEqual(MachineSettings.timeout(["machine", "clone"]), 900)
        XCTAssertLessThanOrEqual(MachineSettings.timeout(["machine", "set"]), 30)
    }
}
