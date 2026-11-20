import XCTest
@testable import DeskCore

final class TaskBoardTests: XCTestCase {
    func term(_ address: String, role: String, team: String, teamRole: String? = nil, created: Int64 = 100, pid: Int64 = 1) -> Term {
        var labels: [String: Any] = ["recovery.role": role, "team.id": team]
        if let teamRole { labels["team.role"] = teamRole }
        return Term(json: ["address": address, "state": "live", "created_ms": created, "pid": pid,
                           "status": ["app": "codex", "state": "idle"], "labels": labels])!
    }
    lazy var lead = term("t1", role: "shop-codex-lead", team: "shop", teamRole: "lead", created: 100, pid: 1)
    lazy var worker = term("t2", role: "shop-builder-000001", team: "shop", created: 200, pid: 2)

    func card(_ id: String, _ state: String, owner: String? = "t2", session: String? = "200:2", kind: String = "card",
              updated: String = "2026-11-20T00:00:10.000+00:00", lead: String? = nil) -> [String: Any] {
        var c: [String: Any] = ["id": id, "state": state, "updated": updated, "kind": kind, "team": "shop"]
        if let owner { c["owner"] = ["address": owner, "session": session as Any, "role": "builder", "spawned": true] }
        if let lead { c["lead"] = lead }
        return c
    }
    func board(_ cards: [[String: Any]]) -> [String: Any] { ["teams": ["shop": ["cards": cards]]] }

    func testUnchangedStampSkipsRun() {
        var runs = 0
        var stamp: Date? = Date(timeIntervalSince1970: 1)
        let source = TaskBoardSource(stamp: { stamp }, run: { runs += 1; return HcResult(code: 0, out: #"{"teams":{}}"#, err: "", timedOut: false) })
        XCTAssertNotNil(source.poll())
        XCTAssertNil(source.poll())
        XCTAssertEqual(runs, 1)
        stamp = Date(timeIntervalSince1970: 2)
        XCTAssertNotNil(source.poll())
        XCTAssertEqual(runs, 2)
    }

    func testFailedRunBacksOffThenRetries() {
        var code: Int32 = 1, runs = 0, clock = Date(timeIntervalSince1970: 100)
        let source = TaskBoardSource(stamp: { Date(timeIntervalSince1970: 1) },
                                     run: { runs += 1; return HcResult(code: code, out: code == 0 ? "{}" : "", err: "x", timedOut: false) },
                                     now: { clock })
        XCTAssertNil(source.poll())
        code = 0
        XCTAssertNil(source.poll())          // same stamp, inside the backoff: no new run
        XCTAssertEqual(runs, 1)
        clock = clock.addingTimeInterval(31)
        XCTAssertNotNil(source.poll())
        XCTAssertEqual(runs, 2)
    }

    func testFlowCardsComeBeforeRealCards() {
        let qa = term("t3", role: "shop-qa", team: "computer", created: 300, pid: 3)
        let clead = term("t4", role: "computer-codex-lead", team: "computer", teamRole: "lead", created: 400, pid: 4)
        let b: [String: Any] = ["teams": ["computer": ["cards": [
            ["id": "computer-000001", "state": "review", "updated": "2026-11-20T00:00:10.000+00:00", "kind": "card",
             "owner": ["address": "t3", "session": "300:3"]],
            ["id": "flow-f1", "state": "working", "updated": "2026-11-20T00:00:09.000+00:00", "kind": "flow",
             "owner": ["address": "shop-qa"], "lead": "computer-codex-lead"]]]]]
        XCTAssertEqual(TaskBoard.flows(board: b, terms: [qa, clead]).map(\.id), ["flow-f1", "computer-000001"])
    }

    func testMissingLedgerFolderSkipsRun() {
        var runs = 0
        let source = TaskBoardSource(stamp: { nil }, run: { runs += 1; return HcResult(code: 0, out: "{}", err: "", timedOut: false) })
        XCTAssertNil(source.poll())
        XCTAssertEqual(runs, 0)
    }

    func testCardStatesMapToFlowPhases() {
        let b = board([card("shop-000001", "working"), card("shop-000002", "review"), card("shop-000003", "done"),
                       card("shop-000004", "cancelled"), card("shop-000005", "queued"), card("shop-000006", "blocked")])
        let flows = TaskBoard.flows(board: b, terms: [lead, worker])
        XCTAssertEqual(flows.map(\.id), ["shop-000001", "shop-000002", "shop-000003", "shop-000004"])
        XCTAssertEqual(flows.map(\.phase), ["working", "result-sent", "acked", "acked"])
        XCTAssertEqual(flows[0].worker.address, "t2")
        XCTAssertEqual(flows[0].lead.address, "t1")
        XCTAssertEqual(flows[0].updatedAt, 1_795_132_810_000)
    }

    func testUnknownOwnerOrLeadIsSkipped() {
        let b = board([card("shop-000001", "working", owner: "t77"), card("shop-000002", "working", owner: nil),
                       card("shop-000003", "working", session: "999:9")])
        XCTAssertTrue(TaskBoard.flows(board: b, terms: [lead, worker]).isEmpty)
        XCTAssertTrue(TaskBoard.flows(board: board([card("shop-000001", "working")]), terms: [worker]).isEmpty)
    }

    func testFlowCardsResolveRoles() {
        let qa = term("t3", role: "shop-qa", team: "shop", created: 300, pid: 3)
        let b = board([card("flow-f1", "review", owner: "shop-qa", session: nil, kind: "flow", lead: "shop-codex-lead")])
        let flows = TaskBoard.flows(board: b, terms: [lead, worker, qa])
        XCTAssertEqual(flows.map(\.worker.address), ["t3"])
        XCTAssertEqual(flows.map(\.phase), ["result-sent"])
    }

    func testCardSignalWinsOverOlderFlow() {
        let book = HandoffBook()
        let l = HandoffParty(address: "t1", session: "100:1", role: "shop-codex-lead")
        let w = HandoffParty(address: "t2", session: "200:2", role: "shop-builder-000001")
        let t0 = 1_795_132_800_000.0
        book.record(HandoffMessage(from: l, to: w, at: t0, body: "do it", source: "receiver"))
        let labelFlow = HandoffFlow(worker: w, lead: l, id: "f1", phase: "working", updatedAt: t0 + 1_000)
        let cardFlows = TaskBoard.flows(board: board([card("shop-000001", "review")]), terms: [lead, worker])
        book.observe(HandoffSignals(status: ["t2": "idle"], session: ["t1": "100:1", "t2": "200:2"],
                                    flows: [labelFlow] + cardFlows, lineage: []), now: t0 + 20_000)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertNotNil(book.edges[0].returnedAt)
        XCTAssertEqual(book.edges[0].flowId, "shop-000001")
    }
}

final class TaskBoardStampTests: XCTestCase {
    func testStampMovesWhenTheComputerListBesideTheLedgerChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let machines = root.appendingPathComponent("machines.json")
        FileManager.default.createFile(atPath: machines.path, contents: Data("{}".utf8))
        let old = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: state.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: machines.path)
        let before = TaskBoardSource.boardStamp(state)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: machines.path)
        XCTAssertNotEqual(TaskBoardSource.boardStamp(state), before)
    }
}
