import Foundation
import XCTest
@testable import DeskCore

final class DirectTargetTests: XCTestCase {
    private final class Core: HcRunning {
        var pid = 71
        var calls: [[String]] = []
        func run(_ args: [String], timeout: TimeInterval) -> HcResult {
            calls.append(args)
            let payload = args.first == "get"
                ? "{\"address\":\"t1\",\"state\":\"live\",\"created_ms\":800,\"pid\":\(pid),\"status\":{\"app\":\"codex\",\"state\":\"idle\"}}"
                : "{\"started\":true,\"turn\":1}"
            return HcResult(code: 0, out: payload, err: "", timedOut: false)
        }
    }

    func testUnlabelledAgentUsesFreshSessionAndDoesNotSendTwice() throws {
        let core = Core()
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let base = AnswerSender(hc: core, ledger: Ledger(dir: fixture.appendingPathComponent("ask")),
                                lockPath: fixture.appendingPathComponent("send.lock").path)
        let sender = DirectSender(base: base, ledger: Ledger(dir: fixture.appendingPathComponent("direct")))
        let term = try XCTUnwrap(Term(json: ["address": "t1", "state": "live", "created_ms": 800, "pid": 71,
                                            "status": ["app": "codex", "state": "idle"]]))
        core.pid = 72
        XCTAssertEqual(sender.send(to: term, messageId: "mold0001", text: "Check the build"), .refused(.sessionChanged))
        XCTAssertFalse(core.calls.contains { $0.first == "send" })
        core.pid = 71
        XCTAssertEqual(sender.send(to: term, messageId: "mnew0001", text: "Check the build"), .sent(turn: 1))
        XCTAssertEqual(sender.send(to: term, messageId: "mnew0001", text: "Check the build"), .refused(.alreadyHandled("sent")))
        XCTAssertEqual(core.calls.filter { $0.first == "send" }.count, 1)
    }
}
