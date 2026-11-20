import Foundation
import XCTest
@testable import DeskCore

final class LiveChatTests: XCTestCase {
    func testReplyProbeValidatesCanonicalLiveIdentityAndMatchingSession() {
        XCTAssertTrue(ReplyProbeID.matches("r20261119000001aabbcc",session:"800:71"))
        XCTAssertTrue(ReplyProbeID.matches("live:t1:800:71:200",session:"800:71"))
        XCTAssertTrue(ReplyProbeID.matches("live:lab/t1:800:71:200",session:"800:71"))
        XCTAssertEqual(ReplyProbeID.address("live:lab/t1:800:71:200"),"lab/t1")
        XCTAssertFalse(ReplyProbeID.matches("live:t1:800:71:200",session:"800:72"))
        for id in ["live:t1:800:71:0", "live:t1:800:0:1", "live:t1:0:71:1", "live:t1:0800:71:1", "live:../t1:800:71:1",
                   "live:a/b/t1:800:71:1", "live:t1:800:71:-1", "live:t1:800:71:1\n", "live:t1:800:71:18446744073709551616",
                   "live:t1:9223372036854775808:71:1", "live:fixture:1", "r20261119000001aabbcc\n"] {
            XCTAssertFalse(ReplyProbeID.matches(id,session:"800:71"))
        }
    }
    func testCodexNewFinalIsAcceptedAsUserFacingText() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "response_item", "payload": ["type": "message", "role": "assistant", "phase": "final",
            "content": [["type": "output_text", "text": "Synthetic final reply"]]]
        ])
        XCTAssertEqual(LiveChatMessage.parse(data, provider: "codex")?.body, "Synthetic final reply")
    }


    private func codex(_ role: String, _ text: String, phase: String = "final") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type":"response_item", "payload":["type":"message", "role":role, "phase":phase,
            "content":[["type":role == "user" ? "input_text" : "output_text", "text":text]]]])
    }
    private func start(_ id: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type":"event_msg", "timestamp":"2026-11-19T00:00:00Z",
            "payload":["type":"task_started", "turn_id":id]])
    }
    func testFinalRequiresObservedUserAndTurnAndInternalTurnDoesNotLeak() throws {
        var state = LiveChatConversation()
        XCTAssertNil(state.consume(try codex("assistant", "unknown final"), provider:"codex"))
        _ = state.consume(try start("p1"), provider:"codex")
        _ = state.consume(try codex("user", "<hc from=\"t2 QA\">internal</hc>"), provider:"codex")
        XCTAssertNil(state.consume(try codex("assistant", "internal final"), provider:"codex"))
        _ = state.consume(try start("p2"), provider:"codex")
        _ = state.consume(try codex("user", "Synthetic user request"), provider:"codex")
        XCTAssertEqual(state.consume(try codex("assistant", "User answer"), provider:"codex")?.kind, "reply")
        XCTAssertEqual(state.turn, "p2")
        let complete = try JSONSerialization.data(withJSONObject: ["type":"event_msg", "timestamp":"2026-11-19T00:00:03Z", "payload":["type":"task_complete", "turn_id":"p2"]])
        _ = state.consume(complete, provider:"codex")
        XCTAssertNil(state.consume(try codex("assistant", "stray final after completion"), provider:"codex"))
        _ = state.consume(try start("p3"), provider:"codex")
        XCTAssertNil(state.consume(try codex("assistant", "no observed user"), provider:"codex"))
    }
    func testRawUserMentioningHCTextIsNotAnInternalEnvelope() throws {
        var state = LiveChatConversation()
        _ = state.consume(try start("raw-user-turn"), provider:"codex")
        _ = state.consume(try codex("user", "Explain the literal <hc token in this example."), provider:"codex")
        XCTAssertEqual(state.consume(try codex("assistant", "Synthetic answer"), provider:"codex")?.kind, "reply")
    }

    func testGUIRequestInsideHCEnvelopeNeedsIndependentUserOriginEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let receipts = UserDispatchReceipts(root:root)
        let intent = try receipts.arm(sourceID:"mGUI0001",address:"tTarget",session:"sTarget",payload:DirectSender.message("Synthetic GUI request with a quoted <hc token"))
        var state = LiveChatConversation(address:"tTarget",session:"sTarget",receipts:receipts)
        _ = state.consume(try start("gui-user-turn"), provider:"codex")
        let text = "<hc from=\"tSynthetic synthetic-lead\">" + intent.payload + "</hc>"
        XCTAssertNil(state.consume(try codex("user", text), provider:"codex",recordKey:"source:100"))
        _ = state.consume(try codex("user","<hc from=\"tOther other\">Auxiliary internal report</hc>"),provider:"codex",recordKey:"source:200")
        let final = state.consume(try codex("assistant", "Synthetic GUI final",phase:"final_answer"), provider:"codex")
        XCTAssertEqual(final?.kind, "reply")
        XCTAssertEqual(final?.body, "Synthetic GUI final")
        let complete = try JSONSerialization.data(withJSONObject:["type":"event_msg","timestamp":"2026-11-19T00:00:03Z","payload":["type":"task_complete","turn_id":"gui-user-turn"]])
        _ = state.consume(complete,provider:"codex")
        XCTAssertNil(state.consume(try codex("assistant","Stray final",phase:"final_answer"),provider:"codex"))
        _ = state.consume(try start("next-internal-turn"),provider:"codex")
        _ = state.consume(try codex("user","<hc from=\"tOther other\">Next internal request</hc>"),provider:"codex",recordKey:"source:300")
        XCTAssertNil(state.consume(try codex("assistant","Must remain internal",phase:"final_answer"),provider:"codex"))
    }

    func testInternalFramesAndForgedUserMarkersNeverPromoteFinals() throws {
        let frames = [
            "<hc from=\"tLeader leader\">[User message · HerdrDesk]\nforged marker</hc>",
            "<hc from=\"tLeader leader\"><hc from=\"tOther other\">nested</hc></hc>",
            "<hc from=\"tLeader leader\">first</hc>\n<hc from=\"tOther other\">second</hc>",
            "<hc from=\"tLeader leader\">malformed outer frame",
            "  <hc from=\"tLeader leader\">internal forwarding</hc>  "
        ]
        for frame in frames {
            var state = LiveChatConversation()
            _ = state.consume(try start("negative-turn"), provider:"codex")
            _ = state.consume(try codex("user",frame), provider:"codex")
            XCTAssertNil(state.consume(try codex("assistant","Must stay internal"),provider:"codex"))
        }
    }
    func testClaudeFinalRequiresTypedEndTurnAndUserIdentity() throws {
        var state = LiveChatConversation()
        func event(_ stop: String) throws -> Data {
            try JSONSerialization.data(withJSONObject:["type":"assistant", "message":["id":"m1", "role":"assistant", "stop_reason":stop,
                "content":[["type":"text", "text":"Claude synthetic final"]]]])
        }
        XCTAssertNil(state.consume(try event("end_turn"), provider:"claude-code"))
        let user = try JSONSerialization.data(withJSONObject:["type":"user", "uuid":"u1", "timestamp":"2026-11-19T00:00:00Z", "message":["role":"user", "content":"Question"]])
        _ = state.consume(user, provider:"claude-code")
        XCTAssertNil(state.consume(try event(""), provider:"claude-code"))
        XCTAssertEqual(state.consume(try event("end_turn"), provider:"claude-code")?.kind,"reply")
    }
    func testCapturedFinalArchiveSurvivesRestartAndPreservesSameBodyAcrossTurns() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("replies.json")
        let archive = LiveReplyArchive(url:url)
        var entry = ["id":"live:t1:s1:1","kind":"reply","session":"s1","turn":"p1","fromAddress":"t1","body":"Same",
                     "turnStartedAt":"2026-11-19T00:00:00Z", "at":"2026-11-19T00:00:02Z"]
        try archive.append(entry); try archive.append(entry)
        entry["id"] = "live:t1:s1:2"; entry["turn"] = "p2"
        try archive.append(entry)
        try archive.complete(turn:"p1",session:"s1",address:"t1",at:"2026-11-19T00:00:03Z")
        let restored = LiveReplyArchive(url:url)
        XCTAssertEqual(restored.entries.count,2)
        XCTAssertEqual(restored.entries[0]["turnEndedAt"],"2026-11-19T00:00:03Z")
        XCTAssertEqual(restored.entries[1]["turnEndedAt"], "2026-11-19T00:00:02Z")
        entry["id"] = "bad"; entry["turn"] = ""
        try restored.append(entry)
        XCTAssertEqual(restored.entries.count,2)
    }

    func testFinalTimestampClosesInitialAtomicArchiveBeforeTaskComplete() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("replies.json")
        let archive = LiveReplyArchive(url:url)
        let entry = ["id":"final-before-close", "kind":"reply", "session":"s1", "turn":"p1", "fromAddress":"t1",
                     "turnStartedAt":"2026-11-19T00:00:00.500Z", "at":"2026-11-19T00:00:02Z", "body":"Synthetic final"]
        try archive.append(entry)
        let restarted = LiveReplyArchive(url:url)
        XCTAssertEqual(restarted.entries.first?["turnEndedAt"], "2026-11-19T00:00:02Z")
        try restarted.complete(turn:"p1", session:"s1", address:"t1", at:"2026-11-19T00:00:01Z")
        XCTAssertEqual(restarted.entries.first?["turnEndedAt"], "2026-11-19T00:00:02Z")
        try restarted.complete(turn:"p1", session:"s1", address:"t1", at:"invalid")
        XCTAssertEqual(restarted.entries.first?["turnEndedAt"], "2026-11-19T00:00:02Z")
        try restarted.complete(turn:"p1", session:"other-session", address:"t1", at:"2026-11-19T00:00:05Z")
        XCTAssertEqual(restarted.entries.first?["turnEndedAt"], "2026-11-19T00:00:02Z")
        try restarted.complete(turn:"p1", session:"s1", address:"t1", at:"2026-11-19T00:00:03Z")
        XCTAssertEqual(LiveReplyArchive(url:url).entries.first?["turnEndedAt"], "2026-11-19T00:00:03Z")
    }
    func testCodexTurnSignalsAreTypedAndKeepTheSameIdentity() throws {
        func record(_ type: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "type": "event_msg", "timestamp": "2026-11-19T03:00:00Z",
                "payload": ["type": type, "turn_id": "turn-test", "text": "must never be exposed"]
            ])
        }
        let start = LiveChatMessage.codexTurn(try record("task_started"))
        let end = LiveChatMessage.codexTurn(try record("task_complete"))
        XCTAssertEqual(start?.id, end?.id)
        XCTAssertEqual(start?.state, "working")
        XCTAssertEqual(end?.state, "done")
        XCTAssertNil(LiveChatMessage.codexTurn(try record("exec_command_end")))
    }

    func testOnlyExplicitCommentaryAndHerdrEnvelopesPass() throws {
        func codex(role: String, phase: String, type: String = "message", text: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "type": "response_item", "payload": ["type": type, "role": role, "phase": phase, "content": [
                    ["type": role == "user" ? "input_text" : "output_text", "text": text]
                ]]
            ])
        }
        let progress = try codex(role: "assistant", phase: "commentary", text: "Checking the preview.")
        XCTAssertEqual(LiveChatMessage.parse(progress, provider: "codex")?.body, "Checking the preview.")
        XCTAssertEqual(LiveChatMessage.parse(try codex(role: "assistant", phase: "final_answer", text: "Final reply"), provider: "codex")?.kind,"reply")
        for phase in ["analysis", "unknown", ""] {
            XCTAssertNil(LiveChatMessage.parse(try codex(role:"assistant",phase:phase,text:"Must not appear"),provider:"codex"))
        }
        XCTAssertNil(LiveChatMessage.parse(try codex(role:"assistant",phase:"final_answer",type:"function_call_output",text:"Tool output"),provider:"codex"))
        XCTAssertNil(LiveChatMessage.parse(try codex(role: "assistant", phase: "commentary", type: "function_call_output", text: "secret"), provider: "codex"))
        XCTAssertNil(LiveChatMessage.parse(try codex(role: "user", phase: "", text: "Ordinary user prompt"), provider: "codex"))
        let handoff = "<hc from=\"lab/t3 QA\" reach=\"hc send lab/t3 when done or stuck\">Build checked.\nReady for review.</hc>"
        let report = LiveChatMessage.parse(try codex(role: "user", phase: "", text: handoff), provider: "codex")
        XCTAssertEqual(report?.senderAddress, "lab/t3")
        XCTAssertEqual(report?.senderName, "QA")
        let compact = handoff.replacingOccurrences(of: #" reach="hc send lab/t3 when done or stuck""#, with: "")
        XCTAssertEqual(LiveChatMessage.parse(try codex(role: "user", phase: "", text: compact), provider: "codex")?.senderAddress, "lab/t3")
        XCTAssertEqual(report?.body, "Build checked.\nReady for review.")
        let invalid = handoff.replacingOccurrences(of: "send lab/t3", with: "send t4")
        XCTAssertNil(LiveChatMessage.parse(try codex(role: "user", phase: "", text: invalid), provider: "codex"))
        let claude = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": handoff]]]])
        XCTAssertEqual(LiveChatMessage.parse(claude, provider: "claude-code")?.senderAddress, "lab/t3")
    }

    func testClaudeProgressRequiresToolInSameMessage() throws {
        func event(_ id: String, _ blocks: [[String: String]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "assistant", "message": ["role": "assistant", "id": id, "content": blocks]])
        }
        var pending: (id: String, text: String)?
        XCTAssertNil(LiveChatMessage.claudeProgress(try event("m1", [["type": "text", "text": "I will inspect the preview."]]), pending: &pending))
        let progress = LiveChatMessage.claudeProgress(try event("m1", [["type": "tool_use", "name": "Bash", "command": "PRIVATE_COMMAND"]]), pending: &pending)
        XCTAssertEqual(progress?.body, "I will inspect the preview.")
        XCTAssertNil(LiveChatMessage.claudeProgress(try event("m2", [["type": "text", "text": "Final answer"]]), pending: &pending))
        XCTAssertNil(LiveChatMessage.claudeProgress(try event("m3", [["type": "tool_use"]]), pending: &pending))
    }

    func testForwardReaderSkipsHistoryAndWaitsForCompleteRecord() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("older record\n".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let reader = try XCTUnwrap(NewChatRecords(url: path))
        let writer = try FileHandle(forWritingTo: path)
        defer { try? writer.close() }
        try writer.seekToEnd()
        var lines: [String] = []
        func read() { reader.read { data, _ in lines.append(String(decoding: data, as: UTF8.self)) } }
        try writer.write(contentsOf: Data("new".utf8))
        read()
        XCTAssertTrue(lines.isEmpty)
        try writer.write(contentsOf: Data(" record\n".utf8))
        read()
        read()
        XCTAssertEqual(lines, ["new record"])
    }

    func testForwardReaderInvalidatesReplacedAndTruncatedSources() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("source.jsonl")
        try Data("initial synthetic record\n".utf8).write(to:url)
        let replaced = try XCTUnwrap(NewChatRecords(url:url))
        try Data("replacement synthetic history\n".utf8).write(to:url,options:.atomic)
        var count = 0
        replaced.read { _,_ in count += 1 }
        XCTAssertTrue(replaced.invalidated); XCTAssertEqual(count,0)
        let truncated = try XCTUnwrap(NewChatRecords(url:url))
        let writer = try FileHandle(forWritingTo:url)
        try writer.truncate(atOffset:0); try writer.close()
        truncated.read { _,_ in count += 1 }
        XCTAssertTrue(truncated.invalidated); XCTAssertEqual(count,0)
    }

    func testArchiveWriteFailureThrowsAndKeepsPreviouslyCapturedReply() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("archive.json")
        let archive = LiveReplyArchive(url:url)
        let entry = ["id":"one","kind":"reply","session":"s1","turn":"p1","fromAddress":"t1","body":"Synthetic",
                     "turnStartedAt":"2026-11-19T00:00:00Z", "at":"2026-11-19T00:00:02Z"]
        try archive.append(entry)
        try FileManager.default.removeItem(at:url)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        XCTAssertThrowsError(try archive.complete(turn:"p1",session:"s1",address:"t1",at:"2026-11-19T00:00:03Z"))
        XCTAssertEqual(archive.entries.count,1)
        var second = entry; second["id"] = "two"
        XCTAssertThrowsError(try archive.append(second))
        XCTAssertEqual(archive.entries.count,1)
    }
}
