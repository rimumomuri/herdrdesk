import Foundation
import XCTest
@testable import DeskCore

final class HandoffTests: XCTestCase {
    let lead = HandoffParty(address:"t1", session:"100:1", role:"shop-codex-lead")
    let prod = HandoffParty(address:"t2", session:"200:2", role:"shop-production")
    let qa = HandoffParty(address:"t3", session:"300:3", role:"shop-qa")
    let t0 = 1_800_000_000_000.0

    func msg(_ from: HandoffParty, _ to: HandoffParty, _ at: Double, _ body: String = "do the thing", source: String = "receiver") -> HandoffMessage {
        HandoffMessage(from:from, to:to, at:at, body:body, source:source)
    }
    func signals(_ status: [String: String], sessions: [String: String]? = nil) -> HandoffSignals {
        HandoffSignals(status:status, session:sessions ?? ["t1":"100:1","t2":"200:2","t3":"300:3"], flows:[], lineage:[])
    }

    func testFirstMessageOpensAssign() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        XCTAssertEqual(book.edges.count, 1)
        XCTAssertEqual(book.edges[0].state, "open")
        XCTAssertEqual(book.cards.last?.kind, "assign")
    }

    func testAcknowledgementRightAfterResultIsAnAdditionNotANewHandoff() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"working"]), now: t0 + 1_000)
        book.observe(signals(["t2":"idle"]), now: t0 + 60_000)
        XCTAssertEqual(book.edges[0].state, "closed")
        book.record(msg(lead, prod, t0 + 61_000, "got the result, checking"))
        XCTAssertEqual(book.edges.count, 1)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertEqual(book.cards.last?.kind, "message")
        book.record(msg(lead, prod, t0 + 400_000, "next task"))
        XCTAssertEqual(book.edges.count, 2)
        XCTAssertEqual(book.cards.last?.kind, "assign")
    }

    func testUserQuestionRightAfterAnAnswerOpensANewHandoff() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.deskReply(from: lead, at: t0 + 9_000, body: "done")
        book.record(msg(.desk, lead, t0 + 20_000, "one more thing", source:"desk"))
        XCTAssertEqual(book.edges.count, 2)
        XCTAssertTrue(book.edges[1].isOpen)
    }

    func testAnswerToTheOtherSidesFinishedRequestDoesNotOpenAHandoff() {
        let book = HandoffBook()
        book.record(msg(prod, lead, t0, "which test environment do you have?"))
        book.observe(signals(["t1":"working"]), now: t0 + 1_000)
        book.observe(signals(["t1":"idle"]), now: t0 + 60_000)
        XCTAssertEqual(book.edges[0].state, "closed")
        book.record(msg(lead, prod, t0 + 1_800_000, "the QA environment is partly ready"))
        XCTAssertEqual(book.edges.count, 1)
        XCTAssertFalse(book.edges.contains { $0.isOpen })
        XCTAssertEqual(book.cards.last?.kind, "reply")
        // the answer is not work handed over, so a busy asker never keeps it waiting
        book.observe(signals(["t2":"working"]), now: t0 + 1_900_000)
        XCTAssertFalse(book.edges.contains { $0.isOpen })
    }

    func testNewRequestAfterTheOtherSideHandedSomethingBackIsStillAHandoff() {
        let book = HandoffBook()
        book.record(msg(prod, lead, t0, "question"))
        book.observe(signals(["t1":"working"]), now: t0 + 1_000)
        book.observe(signals(["t1":"idle"]), now: t0 + 60_000)
        book.record(msg(lead, prod, t0 + 1_800_000, "answer"))
        // only the first word back answers; what follows is new work
        book.record(msg(lead, prod, t0 + 2_100_000, "now build the next screen"))
        XCTAssertEqual(book.edges.count, 2)
        XCTAssertTrue(book.edges[1].isOpen)
        XCTAssertEqual(book.cards.last?.kind, "assign")
    }

    func testLateAnswerOpensAHandoffAsBefore() {
        let book = HandoffBook()
        book.record(msg(prod, lead, t0, "question"))
        book.observe(signals(["t1":"working"]), now: t0 + 1_000)
        book.observe(signals(["t1":"idle"]), now: t0 + 60_000)
        book.record(msg(lead, prod, t0 + 60_000 + HandoffBook.answerWindow + 1, "much later"))
        XCTAssertEqual(book.edges.count, 2)
        XCTAssertEqual(book.cards.last?.kind, "assign")
    }

    func testLaterFollowUpOnOpenHandoffIsAnAddition() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.record(msg(lead, prod, t0 + 300_000, "got it, checking"))
        XCTAssertEqual(book.edges.count, 1)
        XCTAssertEqual(book.cards.last?.kind, "message")
    }

    func testFollowUpWithinTwoMinutesMerges() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.record(msg(lead, prod, t0 + 60_000, "also this"))
        XCTAssertEqual(book.edges.count, 1)
        XCTAssertEqual(book.edges[0].updatedAt, t0 + 60_000)
        XCTAssertEqual(book.cards.last?.kind, "message")
    }

    func testReplyClosesWhenSenderStopsWorking() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"working"]), now: t0 + 1_000)
        book.record(msg(prod, lead, t0 + 50_000, "done"))
        XCTAssertEqual(book.cards.last?.kind, "pending")
        book.observe(signals(["t2":"idle"]), now: t0 + 80_001)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertEqual(book.edges[0].returnedAt, t0 + 50_000)
        XCTAssertEqual(book.cards.last?.kind, "reply")
    }

    func testMidTaskQuestionStaysOpen() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.record(msg(prod, lead, t0 + 50_000, "which branch?"))
        book.observe(signals(["t2":"working"]), now: t0 + 60_000)
        book.observe(signals(["t2":"working"]), now: t0 + 80_001)
        XCTAssertEqual(book.edges[0].state, "open")
        XCTAssertNil(book.edges[0].pendingReplyAt)
        XCTAssertEqual(book.cards.last?.kind, "progress")
    }

    func testUnworkedAgentEdgeBecomesWeak() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"idle"]), now: t0 + 600_001)
        XCTAssertEqual(book.edges[0].state, "weak")
    }

    func testReplyClosesEvenWhenReplierWasStillFinishingUp() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.record(msg(prod, lead, t0 + 50_000, "done, merged"))
        book.observe(signals(["t2":"working"]), now: t0 + 51_000)
        book.observe(signals(["t2":"idle"]), now: t0 + 58_000)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertEqual(book.edges[0].returnedAt, t0 + 50_000)
        XCTAssertEqual(book.cards.last?.kind, "reply")
    }

    func testOldFlowLabelsDoNotCloseANewEdge() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        var s = signals(["t2":"working"])
        s.flows = [HandoffFlow(worker:prod, lead:lead, id:"old", phase:"result-sent", updatedAt:t0 - 3_600_000)]
        s.lineage = [HandoffLineage(from:lead, to:prod, id:"oldEdge", completed:true, at:t0 - 3_600_000)]
        book.observe(s, now: t0 + 1_000)
        XCTAssertEqual(book.edges[0].state, "open")
        XCTAssertEqual(book.edges[0].signal, "transcript")
    }

    func testDeskReplyCardCarriesTheReply() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, "please review", source:"desk"))
        book.deskReply(from: lead, at: t0 + 9_000, body: "reviewed, two fixes")
        XCTAssertEqual(book.cards.last?.body, "reviewed, two fixes")
    }

    func testEdgeClosesWhenItsTerminalIsGone() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t1":"idle"], sessions:["t1":"100:1"]), now: t0 + 1_000)
        XCTAssertEqual(book.edges[0].state, "closed")
    }

    func testUnknownSessionTargetIsNotClosedAsGone() {
        let book = HandoffBook()
        let remote = HandoffParty(address:"mbp/t5", session:"", role:"")
        book.record(msg(lead, remote, t0, source:"sender"))
        book.observe(signals(["t1":"idle"], sessions:["t1":"100:1"]), now: t0 + 1_000)
        XCTAssertEqual(book.edges[0].state, "open")
    }

    func testEmptyTerminalListClosesNothing() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals([:], sessions:[:]), now: t0 + 1_000)
        XCTAssertEqual(book.edges[0].state, "open")
    }

    func testSecondReplyBeforeResolutionDoesNotStrandFirstCard() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.record(msg(prod, lead, t0 + 10_000, "question one"))
        book.record(msg(prod, lead, t0 + 20_000, "question two"))
        XCTAssertEqual(book.cards.filter { $0.kind == "pending" }.count, 1)
    }

    func testSnapshotBodiesAreShortAndSignatureTracksChanges() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0, String(repeating: "x", count: 1500)))
        let cards = book.webSnapshot(now: t0)["cards"] as? [[String: Any]]
        XCTAssertLessThanOrEqual((cards?.first?["body"] as? String)?.count ?? 0, 300)
        let before = book.signature(now: t0)
        book.record(msg(prod, lead, t0 + 5_000, "done"))
        XCTAssertNotEqual(book.signature(now: t0 + 5_000), before)
    }

    func testDeskEdgeClosesAfterWorkThenIdle() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.observe(signals(["t1":"working"]), now: t0 + 5_000)
        XCTAssertEqual(book.edges[0].state, "open")
        book.observe(signals(["t1":"idle"]), now: t0 + 10_000)
        XCTAssertEqual(book.edges[0].state, "closed")
    }

    func testDeskEdgeStaysOpenWhileTargetWaitsOnOthers() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.observe(signals(["t1":"working"]), now: t0 + 5_000)
        book.record(msg(lead, prod, t0 + 6_000))
        book.observe(signals(["t1":"idle","t2":"working"]), now: t0 + 10_000)
        XCTAssertEqual(book.edges.first { $0.from == .desk }?.state, "open")
    }

    func testDeskEdgeClosesSilentlyWithoutWork() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.observe(signals(["t1":"idle"]), now: t0 + 600_001)
        XCTAssertEqual(book.edges[0].state, "closed")
    }

    func testDeskReplyClosesDeskEdge() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.deskReply(from: lead, at: t0 + 9_000, body: "all done")
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertEqual(book.edges[0].returnedAt, t0 + 9_000)
        XCTAssertEqual(book.cards.last?.kind, "reply")
    }

    func testPublishedReplyClosesDeskEdgeWhileLeadStillDelegates() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, "done yet?", source:"desk"))
        book.record(msg(lead, prod, t0 + 1_000))
        book.observe(signals(["t1":"working", "t2":"working"]), now: t0 + 2_000)
        let cardsBefore = book.cards.count
        book.publishedReply(role: lead.role, session: lead.session, at: t0 + 9_000)
        book.observe(signals(["t1":"idle", "t2":"working"]), now: t0 + 10_000)
        let desk = book.edges.first { $0.from == .desk }!
        XCTAssertEqual(desk.state, "closed")
        XCTAssertEqual(desk.returnedAt, t0 + 9_000)
        XCTAssertEqual(book.edges.first { $0.from == lead }!.state, "open")
        // The published reply is already shown from its own record; a second copy would duplicate it.
        XCTAssertEqual(book.cards.count, cardsBefore)
    }

    func testPublishedReplyBeforeLatestQuestionKeepsDeskEdgeOpen() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, "first", source:"desk"))
        book.record(msg(.desk, lead, t0 + 600_000, "done yet?", source:"desk"))
        book.publishedReply(role: lead.role, session: lead.session, at: t0 + 300_000)
        XCTAssertTrue(book.edges.first { $0.from == .desk }!.isOpen)
    }

    func testPublishedReplyFromAnotherSessionKeepsDeskEdgeOpen() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.publishedReply(role: lead.role, session: "999:9", at: t0 + 9_000)
        book.publishedReply(role: prod.role, session: prod.session, at: t0 + 9_000)
        XCTAssertTrue(book.edges[0].isOpen)
    }

    func testAgentEdgeClosesWhenReceiverFinishes() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"working"]), now: t0 + 1_000)
        book.observe(signals(["t2":"idle"]), now: t0 + 60_000)
        XCTAssertEqual(book.edges[0].state, "closed")
    }

    func testAgentEdgeStaysOpenWhileReceiverDelegatesFurther() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"working"]), now: t0 + 1_000)
        book.record(msg(prod, qa, t0 + 2_000))
        book.observe(signals(["t2":"idle", "t3":"working"]), now: t0 + 60_000)
        XCTAssertTrue(book.edges.first { $0.from == lead }!.isOpen)
    }

    func testReportToReceiverStuckWorkingClosesAfterWeakWindow() {
        let book = HandoffBook()
        book.record(msg(lead, qa, t0, "final result"))
        var s = signals(["t3":"working"])
        s.statusSince = ["t3": t0 - 7 * 3_600_000]
        book.observe(s, now: t0 + 1_000)
        XCTAssertTrue(book.edges[0].isOpen)
        book.observe(s, now: t0 + 600_001)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertNil(book.edges[0].returnedAt)
    }

    func testRecentlyWorkingReceiverIsNotTreatedAsStuck() {
        let book = HandoffBook()
        book.record(msg(lead, qa, t0))
        var s = signals(["t3":"working"])
        s.statusSince = ["t3": t0 - 60_000]
        book.observe(s, now: t0 + 600_001)
        XCTAssertEqual(book.edges[0].state, "open")
    }

    func testSessionChangeClosesEdge() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"working"], sessions:["t1":"100:1","t2":"999:9"]), now: t0 + 1_000)
        XCTAssertEqual(book.edges[0].state, "closed")
    }

    func testStaleAfterSixHours() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"working"]), now: t0 + 1_000)
        book.observe(signals(["t2":"idle"]), now: t0 + 21_600_001)
        XCTAssertEqual(book.edges[0].state, "stale")
    }

    func testFlowOverridesTranscript() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.record(msg(prod, lead, t0 + 1_000, "ok"))
        var s = signals(["t2":"idle"])
        s.flows = [HandoffFlow(worker:prod, lead:lead, id:"f1", phase:"working", updatedAt:t0 + 2_000)]
        book.observe(s, now: t0 + 40_000)
        XCTAssertEqual(book.edges[0].state, "open")
        XCTAssertEqual(book.edges[0].signal, "flow")
        XCTAssertEqual(book.edges[0].flowId, "f1")
    }

    func testFlowResultSentReturns() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        var s = signals(["t2":"idle"])
        s.flows = [HandoffFlow(worker:prod, lead:lead, id:"f1", phase:"result-sent", updatedAt:t0 + 4_000)]
        book.observe(s, now: t0 + 5_000)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertEqual(book.edges[0].returnedAt, t0 + 5_000)
    }

    func testLineageCompletionCloses() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        var s = signals(["t2":"idle"])
        s.lineage = [HandoffLineage(from:lead, to:prod, id:"e1", completed:true, at:t0 + 4_000)]
        book.observe(s, now: t0 + 5_000)
        XCTAssertEqual(book.edges[0].state, "closed")
        XCTAssertEqual(book.edges[0].signal, "lineage")
    }

    func testEdgesAreKeyedBySessionNotRole() {
        let book = HandoffBook()
        let twin = HandoffParty(address:"t9", session:"900:9", role:"shop-production")
        book.record(msg(lead, prod, t0))
        book.record(msg(lead, twin, t0 + 1_000))
        XCTAssertEqual(book.edges.count, 2)
    }

    func testSenderAndReceiverCopiesDedupe() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0, "review 348", source:"sender"))
        book.record(msg(lead, prod, t0 + 2_000, "review 348", source:"receiver"))
        XCTAssertEqual(book.cards.count, 1)
    }

    func testPruneNeverThrowsAndCaps() {
        let book = HandoffBook()
        for i in 0..<1200 { book.record(msg(lead, prod, t0 + Double(i) * 200_000, "task \(i)")) }
        book.prune(now: t0 + 1200 * 200_000)
        XCTAssertLessThanOrEqual(book.cards.count, 1000)
        XCTAssertEqual(book.cards.last?.body, "task 1199")
    }

    func testPruneDropsOldClosedEdges() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.observe(signals(["t2":"idle"], sessions:["t2":"999:9"]), now: t0 + 1_000)
        book.prune(now: t0 + 604_800_001 + 1_000)
        XCTAssertTrue(book.edges.isEmpty)
    }

    func testSnapshotShowsReturningForThreeSeconds() {
        let book = HandoffBook()
        book.record(msg(.desk, lead, t0, source:"desk"))
        book.deskReply(from: lead, at: t0 + 10_000, body: "ok")
        let shown = book.webSnapshot(now: t0 + 12_000)["edges"] as? [[String: Any]]
        XCTAssertEqual(shown?.first?["state"] as? String, "returning")
        let later = book.webSnapshot(now: t0 + 14_000)["edges"] as? [[String: Any]]
        XCTAssertEqual(later?.count, 0)
    }

    func testReloadMarksOpenEdgesUnconfirmed() {
        let book = HandoffBook()
        book.record(msg(lead, prod, t0))
        book.markReloaded()
        XCTAssertEqual(book.edges[0].state, "unconfirmed")
        book.observe(signals(["t2":"working"]), now: t0 + 1_000)
        XCTAssertEqual(book.edges[0].state, "open")
    }
}

final class OutgoingSendTests: XCTestCase {
    func line(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    func claude(_ command: String) -> Data {
        line(["type":"assistant","message":["role":"assistant","id":"m1","content":[["type":"tool_use","id":"u1","name":"Bash","input":["command":command]]]]])
    }
    func codex(_ arguments: [String: Any], name: String = "exec_command") -> Data {
        let args = String(data: line(arguments), encoding: .utf8)!
        return line(["type":"response_item","payload":["type":"function_call","name":name,"arguments":args,"call_id":"c1"]])
    }

    func testClaudeBashHcSendIsDetected() {
        let r = LiveChatMessage.outgoingSend(claude("hc send t10y \"fix the links\""), provider:"claude-code")
        XCTAssertEqual(r?.target, "t10y"); XCTAssertEqual(r?.body, "fix the links")
    }
    func testCodexExecCommandHcSendIsDetected() {
        let r = LiveChatMessage.outgoingSend(codex(["cmd":"hc send --json t10y 'run QA'"]), provider:"codex")
        XCTAssertEqual(r?.target, "t10y"); XCTAssertEqual(r?.body, "run QA")
    }
    func testCodexShellArrayAndPathPrefixAreDetected() {
        let r = LiveChatMessage.outgoingSend(codex(["command":["bash","-lc","cd /tmp && ~/.local/bin/hc send shop-qa \"check 348\""]], name:"shell"), provider:"codex")
        XCTAssertEqual(r?.target, "shop-qa"); XCTAssertEqual(r?.body, "check 348")
    }
    func testHeredocBodyIsDetected() {
        let r = LiveChatMessage.outgoingSend(claude("hc send t2 \"$(cat <<'EOF'\nline one\nline \"two\"\nEOF\n)\""), provider:"claude-code")
        XCTAssertEqual(r?.target, "t2"); XCTAssertEqual(r?.body, "line one\nline \"two\"")
    }
    func testUnquotedWordsAreJoined() {
        XCTAssertEqual(LiveChatMessage.outgoingSend(claude("hc send t2 please review"), provider:"claude-code")?.body, "please review")
    }
    func testOtherCommandsAndHcReadAreIgnored() {
        XCTAssertNil(LiveChatMessage.outgoingSend(claude("hc read t10y"), provider:"claude-code"))
        XCTAssertNil(LiveChatMessage.outgoingSend(claude("echo hc send x hi"), provider:"claude-code"))
        XCTAssertNil(LiveChatMessage.outgoingSend(claude("hc send t2"), provider:"claude-code"))
        XCTAssertNil(LiveChatMessage.outgoingSend(claude("hc send t2 \"unterminated"), provider:"claude-code"))
        XCTAssertNil(LiveChatMessage.outgoingSend(codex(["cmd":"ls"]), provider:"codex"))
    }
}

final class HandoffStoreTests: XCTestCase {
    let lead = HandoffParty(address:"t1", session:"100:1", role:"lead")
    let prod = HandoffParty(address:"t2", session:"200:2", role:"prod")
    func url() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("handoffs.json")
    }
    func testStoreRoundTripsAndPermissions() throws {
        let u = url(), book = HandoffBook()
        book.record(HandoffMessage(from:lead, to:prod, at:1_000, body:"go", source:"receiver"))
        try HandoffStore(url:u).save(book)
        let perms = try FileManager.default.attributesOfItem(atPath:u.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
        let loaded = HandoffStore(url:u).load()
        XCTAssertEqual(loaded.edges.count, 1)
        XCTAssertEqual(loaded.cards.count, 1)
    }
    func testReloadedOpenEdgesAreUnconfirmed() throws {
        let u = url(), book = HandoffBook()
        book.record(HandoffMessage(from:lead, to:prod, at:1_000, body:"go", source:"receiver"))
        try HandoffStore(url:u).save(book)
        XCTAssertEqual(HandoffStore(url:u).load().edges.first?.state, "unconfirmed")
    }
    func testCorruptFileLoadsEmpty() throws {
        let u = url()
        try FileManager.default.createDirectory(at:u.deletingLastPathComponent(), withIntermediateDirectories:true)
        try Data("{not json".utf8).write(to:u)
        XCTAssertTrue(HandoffStore(url:u).load().edges.isEmpty)
    }
}

final class HandoffTargetTests: XCTestCase {
    func term(_ address: String, role: String, name: String? = nil, pid: Int) -> Term {
        var json: [String: Any] = ["address": address, "state": "live", "created_ms": 1, "pid": pid, "labels": ["recovery.role": role]]
        if let name { json["name"] = name }
        return Term(json: json)!
    }
    func testAddressWinsAndUniqueRoleResolves() {
        let terms = [term("t1", role: "lead", pid: 1), term("t2", role: "qa", name: "shop-qa", pid: 2)]
        XCTAssertEqual(HandoffTarget.resolve("t1", in: terms)?.address, "t1")
        XCTAssertEqual(HandoffTarget.resolve("shop-qa", in: terms)?.address, "t2")
        XCTAssertEqual(HandoffTarget.resolve("qa", in: terms)?.address, "t2")
    }
    func testAmbiguousRoleResolvesToNothing() {
        let terms = [term("t1", role: "qa", pid: 1), term("t2", role: "qa", pid: 2)]
        XCTAssertNil(HandoffTarget.resolve("qa", in: terms))
    }
}
