import Foundation
import XCTest
import Darwin
@testable import DeskCore

final class UserDispatchTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return root
    }
    private func wrapped(_ text: String) -> String { "<hc from=\"tSynthetic synthetic-lead\">" + text + "</hc>" }

    func testClaimRequiresExactBindingPayloadAndGenerationAndRejectsReplay() throws {
        let root = try fixture().appendingPathComponent("receipts")
        let store = UserDispatchReceipts(root:root,generation:"app-A")
        let now = Date()
        let intent = try store.arm(sourceID:"mFixture1",address:"t1",session:"s1",payload:"Synthetic user text",now:now)
        XCTAssertFalse(store.claim(text:wrapped(intent.payload),address:"t2",session:"s1",turn:"p1",recordKey:"source:1",now:now))
        XCTAssertFalse(store.claim(text:wrapped(intent.payload),address:"t1",session:"s2",turn:"p1",recordKey:"source:1",now:now))
        XCTAssertFalse(store.claim(text:intent.payload + "\n",address:"t1",session:"s1",turn:"p1",recordKey:"source:1",now:now))
        XCTAssertFalse(store.claim(text:wrapped(wrapped(intent.payload)),address:"t1",session:"s1",turn:"p1",recordKey:"source:1",now:now))
        XCTAssertFalse(UserDispatchReceipts(root:root,generation:"app-B").claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:1",now:now))
        XCTAssertTrue(store.claim(text:wrapped(intent.payload),address:"t1",session:"s1",turn:"p1",recordKey:"source:1",now:now))
        XCTAssertTrue(store.claim(text:wrapped(intent.payload),address:"t1",session:"s1",turn:"p1",recordKey:"source:1",now:now.addingTimeInterval(1200)))
        XCTAssertFalse(store.claim(text:wrapped(intent.payload),address:"t1",session:"s1",turn:"p1",recordKey:"source:2",now:now))
        XCTAssertFalse(store.claim(text:wrapped(intent.payload),address:"t1",session:"s1",turn:"p2",recordKey:"source:1",now:now))
        XCTAssertThrowsError(try UserDispatchReceipts(root:root,generation:"new-app").arm(sourceID:"mFixture1",address:"t1",session:"s1",payload:"Another attempt",now:now))
        XCTAssertNoThrow(try store.arm(sourceID:"different-question",address:"t1",session:"s1",payload:"Synthetic user text",now:now))
        XCTAssertNoThrow(try store.arm(sourceID:"mFixture1",address:"t1",session:"new-session",payload:"Synthetic user text",now:now))
        let bytes = try String(contentsOf:root.appendingPathComponent(intent.id + ".json"),encoding:.utf8)
        XCTAssertFalse(bytes.contains("Synthetic user text"))
        let addressOnly = try store.arm(sourceID:"address-only-frame",address:"t1",session:"s1",payload:"Synthetic user text",now:now)
        XCTAssertFalse(store.claim(text:"<hc from=\"tLauncher\" reach=\"hc send tOther\">" + addressOnly.payload + "</hc>",address:"t1",session:"s1",turn:"p2",recordKey:"source:address",now:now))
        XCTAssertTrue(store.claim(text:"<hc from=\"tLauncher\">" + addressOnly.payload + "</hc>",address:"t1",session:"s1",turn:"p2",recordKey:"source:address",now:now))
    }

    func testReservedObserverEpochIsSharedBySenderAndFirstOrRetainedSource() throws {
        let root = try fixture().appendingPathComponent("receipts")
        let store = UserDispatchReceipts(root:root,generation:"app-A")
        let intent = try store.arm(sourceID:"mBeforeSource",address:"t1",session:"s1",payload:"Synthetic")
        let source = LiveChatConversation(address:"t1",session:"s1",receipts:store)
        let epoch = try XCTUnwrap(source.boundObserverEpoch)
        XCTAssertEqual(try store.observerEpoch(address:"t1",session:"s1"),epoch)
        XCTAssertEqual(try UserDispatchReceipts(root:root,generation:"app-A").observerEpoch(address:"t1",session:"s1"),epoch)
        XCTAssertTrue(store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"retained-source:100",observerEpoch:epoch))
        XCTAssertTrue(store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"retained-source:100",observerEpoch:epoch))
    }

    func testObserverReplacementRejectsOldUnclaimedTokenAndStaleSourceButKeepsCapturedArchive() throws {
        let folder = try fixture(); let store = UserDispatchReceipts(root:folder.appendingPathComponent("receipts"))
        let old = try store.arm(sourceID:"old-unclaimed",address:"t1",session:"s1",payload:"Synthetic old")
        let oldEpoch = try store.observerEpoch(address:"t1",session:"s1")
        let other = try store.arm(sourceID:"other-session",address:"t1",session:"s2",payload:"Synthetic other")
        let otherEpoch = try store.observerEpoch(address:"t1",session:"s2")
        try store.rotateObserverEpoch(address:"t1",session:"s1",expected:oldEpoch)
        let newEpoch = try store.observerEpoch(address:"t1",session:"s1")
        XCTAssertNotEqual(oldEpoch,newEpoch)
        try store.rotateObserverEpoch(address:"t1",session:"s1",expected:oldEpoch)
        XCTAssertEqual(try store.observerEpoch(address:"t1",session:"s1"),newEpoch)
        XCTAssertEqual(try store.observerEpoch(address:"t1",session:"s2"),otherEpoch)
        XCTAssertFalse(store.claim(text:old.payload,address:"t1",session:"s1",turn:"new-turn",recordKey:"replacement:100",observerEpoch:newEpoch))
        let fresh = try store.arm(sourceID:"new-intent",address:"t1",session:"s1",payload:"Synthetic fresh")
        XCTAssertFalse(store.claim(text:fresh.payload,address:"t1",session:"s1",turn:"new-turn",recordKey:"old-source:200",observerEpoch:oldEpoch))
        XCTAssertTrue(store.claim(text:fresh.payload,address:"t1",session:"s1",turn:"new-turn",recordKey:"replacement:200",observerEpoch:newEpoch))
        XCTAssertTrue(store.claim(text:other.payload,address:"t1",session:"s2",turn:"other-turn",recordKey:"other-source:100",observerEpoch:otherEpoch))
        let archiveURL = folder.appendingPathComponent("captured.json")
        let archive = LiveReplyArchive(url:archiveURL)
        try archive.append(["id":"live:t1:800:71:200","kind":"reply","session":"s1","turn":"new-turn","body":"Previously captured synthetic final"])
        try store.rotateObserverEpoch(address:"t1",session:"s1",expected:newEpoch)
        XCTAssertEqual(LiveReplyArchive(url:archiveURL).entries.count,1)
        XCTAssertThrowsError(try store.arm(sourceID:"new-intent",address:"t1",session:"s1",payload:"Attempted duplicate"))
    }

    func testFailedObserverRotationStillRevokesOldEpochAfterStorageRecovery() throws {
        let root = try fixture().appendingPathComponent("receipts"); let store = UserDispatchReceipts(root:root)
        let old = try store.arm(sourceID:"pending",address:"t1",session:"s1",payload:"Synthetic")
        let epoch = try store.observerEpoch(address:"t1",session:"s1")
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
        XCTAssertThrowsError(try store.rotateObserverEpoch(address:"t1",session:"s1",expected:epoch))
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)
        let replacement = try store.observerEpoch(address:"t1",session:"s1")
        XCTAssertNotEqual(epoch,replacement)
        XCTAssertFalse(store.claim(text:old.payload,address:"t1",session:"s1",turn:"p1",recordKey:"new-source:100",observerEpoch:replacement))
    }

    func testTTLIsForFirstClaimAndDeliveryFailureDoesNotCancelObservedOrigin() throws {
        let store = UserDispatchReceipts(root:try fixture().appendingPathComponent("receipts"))
        let now = Date()
        let expired = try store.arm(sourceID:"expired",address:"t1",session:"s1",payload:"expired",now:now)
        XCTAssertFalse(store.claim(text:expired.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:1",now:now.addingTimeInterval(601)))
        for (index,outcome) in [SendOutcome.sent(turn:1),.notSent("synthetic definite failure"),.needsCheck("synthetic timeout")].enumerated() {
            let intent = try store.arm(sourceID:"delivery\(index)",address:"t1",session:"s1",payload:"Synthetic",now:now)
            try store.recordSenderResult(intent.id,outcome:outcome)
            XCTAssertTrue(store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:intent.id,now:now))
            try store.recordSenderResult(intent.id,outcome:.notSent("late synthetic failure"))
            XCTAssertTrue(store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:intent.id,now:now.addingTimeInterval(1200)))
        }
    }

    func testClaimWaitsForShortReceiptTransactionInsteadOfLosingInput() throws {
        let root = try fixture().appendingPathComponent("receipts")
        let store = UserDispatchReceipts(root:root)
        let intent = try store.arm(sourceID:"contention",address:"t1",session:"s1",payload:"Synthetic")
        let fd = open(root.appendingPathComponent(".claim.lock").path,O_RDWR)
        XCTAssertGreaterThanOrEqual(fd,0)
        XCTAssertEqual(flock(fd,LOCK_EX),0)
        let done = DispatchSemaphore(value:0)
        let resultLock = NSLock(); var result = false
        DispatchQueue.global().async {
            let value = store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:1")
            resultLock.lock(); result = value; resultLock.unlock(); done.signal()
        }
        let early = done.wait(timeout:.now() + 0.05)
        flock(fd,LOCK_UN); close(fd)
        XCTAssertEqual(early,.timedOut)
        if early == .timedOut { XCTAssertEqual(done.wait(timeout:.now() + 3),.success) }
        resultLock.lock(); let captured = result; resultLock.unlock()
        XCTAssertTrue(captured)
    }

    func testConcurrentArmResultAndClaimPreserveAllLegitimateObservations() throws {
        let root = try fixture().appendingPathComponent("receipts")
        let producer = UserDispatchReceipts(root:root,generation:"same-app")
        let observer = UserDispatchReceipts(root:root,generation:"same-app")
        let intents = try (0..<12).map { try producer.arm(sourceID:"request-\($0)",address:"t1",session:"s1",payload:"Synthetic \($0)") }
        let resultsLock = NSLock(); var passed = 0
        DispatchQueue.concurrentPerform(iterations:36) { index in
            let item = index / 3
            var ok = false
            do {
                switch index % 3 {
                case 0:
                    _ = try producer.arm(sourceID:"concurrent-new-\(item)",address:"t1",session:"s1",payload:"Synthetic new")
                    ok = true
                case 1:
                    try producer.recordSenderResult(intents[item].id,outcome:.notSent("Synthetic failure"))
                    ok = true
                default:
                    ok = observer.claim(text:intents[item].payload,address:"t1",session:"s1",turn:"p\(item)",recordKey:"source:\(item)")
                }
            } catch {}
            resultsLock.lock(); if ok { passed += 1 }; resultsLock.unlock()
        }
        XCTAssertEqual(passed,36)
        for item in 0..<12 {
            XCTAssertTrue(observer.claim(text:intents[item].payload,address:"t1",session:"s1",turn:"p\(item)",recordKey:"source:\(item)"))
        }
    }

    func testUnsafeReceiptDirectoryAndSymlinkFailClosed() throws {
        let folder = try fixture()
        let root = folder.appendingPathComponent("receipts")
        let store = UserDispatchReceipts(root:root)
        let intent = try store.arm(sourceID:"safe",address:"t1",session:"s1",payload:"Synthetic")
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
        XCTAssertFalse(store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:1"))
        XCTAssertThrowsError(try store.arm(sourceID:"unsafe",address:"t1",session:"s1",payload:"Synthetic"))
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:root)
        XCTAssertFalse(UserDispatchReceipts(root:link).claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:1"))
        XCTAssertFalse(UserDispatchReceipts(root:URL(fileURLWithPath:"/private")).claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:1"))
    }

    func testLocalReceiptWithoutTypedInputAndToolCopiesCannotCreateReply() throws {
        let store = UserDispatchReceipts(root:try fixture().appendingPathComponent("receipts"))
        let intent = try store.arm(sourceID:"mNoInput1",address:"t1",session:"s1",payload:"Synthetic GUI request")
        try store.recordSenderResult(intent.id,outcome:.sent(turn:1))
        var state = LiveChatConversation(address:"t1",session:"s1",receipts:store)
        let start = try JSONSerialization.data(withJSONObject:["type":"event_msg","timestamp":"2026-11-19T00:00:00Z","payload":["type":"task_started","turn_id":"p1"]])
        let final = try JSONSerialization.data(withJSONObject:["type":"response_item","payload":["type":"message","role":"assistant","phase":"final","content":[["type":"output_text","text":"Must not appear"]]]])
        _ = state.consume(start,provider:"codex")
        XCTAssertNil(state.consume(final,provider:"codex"))
        let tool = try JSONSerialization.data(withJSONObject:["type":"response_item","payload":["type":"function_call_output","role":"user","content":[["type":"input_text","text":intent.payload]]]])
        XCTAssertNil(state.consume(tool,provider:"codex",recordKey:"source:tool"))
        XCTAssertNil(state.consume(final,provider:"codex"))
        XCTAssertTrue(store.claim(text:intent.payload,address:"t1",session:"s1",turn:"p1",recordKey:"source:real-user"))
    }

    func testClaudeOriginIsLatchedThroughAuxiliaryHCAndResetsAtEndTurn() throws {
        let store = UserDispatchReceipts(root:try fixture().appendingPathComponent("receipts"))
        let intent = try store.arm(sourceID:"mClaude1",address:"t1",session:"s1",payload:"Synthetic GUI request")
        var state = LiveChatConversation(address:"t1",session:"s1",receipts:store)
        func user(_ id: String,_ text: String, at: String = "2026-11-19T00:00:00Z") throws -> Data {
            try JSONSerialization.data(withJSONObject:["type":"user","uuid":id,"timestamp":at,"message":["role":"user","content":text]])
        }
        let final = try JSONSerialization.data(withJSONObject:["type":"assistant","message":["role":"assistant","id":"assistant1","stop_reason":"end_turn","content":[["type":"text","text":"Synthetic Claude final"]]]])
        _ = state.consume(try user("completed-internal",wrapped("Internal-only request")),provider:"claude-code",recordKey:"source:0")
        XCTAssertNil(state.consume(final,provider:"claude-code"))
        XCTAssertNil(state.consume(try user("first-user",wrapped(intent.payload),at:"2026-11-19T00:00:01Z"),provider:"claude-code",recordKey:"source:1"))
        XCTAssertEqual(state.turn,"first-user")
        XCTAssertEqual(state.startedAt,"2026-11-19T00:00:01Z")
        _ = state.consume(try user("auxiliary-user",wrapped("Internal report")),provider:"claude-code",recordKey:"source:2")
        XCTAssertEqual(state.turn,"first-user")
        XCTAssertEqual(state.consume(final,provider:"claude-code")?.kind,"reply")
        _ = state.consume(try user("next-internal",wrapped("New internal request")),provider:"claude-code",recordKey:"source:3")
        XCTAssertNil(state.consume(final,provider:"claude-code"))
    }

    private final class Core: HcRunning {
        let source: URL
        var callback: (() -> Void)?
        var outcome = HcResult(code:0,out:"{\"started\":false}",err:"",timedOut:false)
        var sends = 0
        var putFails = false
        let target: [String: Any] = ["address":"t1", "state":"live", "pid":71, "created_ms":800,
            "status":["app":"codex","state":"idle"],"labels":["recovery.role":"synthetic","ask.id":"qSynthetic1","ask.text":"Synthetic?","ask.session":"800:71"]]
        init(source: URL) { self.source = source }
        func run(_ args: [String], timeout: TimeInterval) -> HcResult {
            if args.first == "send" {
                sends += 1
                let rows: [[String:Any]] = [
                    ["type":"event_msg","timestamp":"2026-11-19T00:00:00Z","payload":["type":"task_started","turn_id":"p1"]],
                    ["type":"response_item","payload":["type":"message","role":"user","content":[["type":"input_text","text":"<hc from=\"tLauncher launcher\">" + (args.last ?? "") + "</hc>"]]]],
                    ["type":"response_item","timestamp":"2026-11-19T00:00:02Z","payload":["type":"message","role":"assistant","phase":"final_answer","content":[["type":"output_text","text":"Synthetic captured final"]]]],
                    ["type":"event_msg","timestamp":"2026-11-19T00:00:03Z","payload":["type":"task_complete","turn_id":"p1"]]
                ]
                do {
                    let writer = try FileHandle(forWritingTo:source); try writer.seekToEnd()
                    for row in rows { try writer.write(contentsOf:JSONSerialization.data(withJSONObject:row)); try writer.write(contentsOf:Data([10])) }
                    try writer.close()
                } catch { return HcResult(code:1,out:"",err:"synthetic fixture write failed",timedOut:false) }
                callback?()
                return outcome
            }
            var object: [String:Any] = [:]
            if args.first == "get" { object = target }
            if args.first == "ls" { object = ["terminals":[target]] }
            if args.first == "put" { object = putFails ? [:] : ["path":"/synthetic/landed.png"] }
            return HcResult(code:0,out:String(data:try! JSONSerialization.data(withJSONObject:object),encoding:.utf8)!,err:"",timedOut:false)
        }
    }

    func testRealDirectAndQuestionSendReaderConversationArchivePipelineDespiteFalseAck() throws {
        for scenario in ["direct", "direct-image", "question"] {
            let question = scenario == "question"
            let folder = try fixture(); let source = folder.appendingPathComponent("new-provider.jsonl")
            try Data("synthetic history must be skipped\n".utf8).write(to:source)
            let reader = try XCTUnwrap(NewChatRecords(url:source))
            let store = UserDispatchReceipts(root:folder.appendingPathComponent("receipts"))
            var conversation = LiveChatConversation(address:"t1",session:"800:71",receipts:store)
            let archiveURL = folder.appendingPathComponent("live-replies.json")
            let archive = LiveReplyArchive(url:archiveURL)
            let core = Core(source:source)
            core.callback = {
                reader.read { bytes,offset in
                    if let message = conversation.consume(bytes,provider:"codex",recordKey:"fixture-source:\(offset)"), message.kind == "reply" {
                        try! archive.append(["id":"live:t1:800:71:\(offset)","kind":message.kind,"body":message.body,"role":"synthetic",
                            "session":"800:71","fromAddress":"t1","turn":conversation.turn,"turnStartedAt":conversation.startedAt,"at":"2026-11-19T00:00:02Z"])
                    }
                }
            }
            let ledger = Ledger(dir:folder.appendingPathComponent("ledger"))
            let base = AnswerSender(hc:core,ledger:ledger,lockPath:folder.appendingPathComponent("send.lock").path,originReceipts:store)
            if question {
                XCTAssertEqual(base.send(role:"synthetic",questionId:"qSynthetic1",text:"Synthetic answer"),.notSent("시작되지 않음"))
                XCTAssertEqual(ledger.read("qSynthetic1")?.state,"not_sent")
                _ = base.send(role:"synthetic",questionId:"qSynthetic1",text:"Synthetic answer")
                XCTAssertEqual(core.sends,1)
            } else {
                let directLedger = Ledger(dir:folder.appendingPathComponent("direct"))
                let direct = DirectSender(base:base,ledger:directLedger)
                let images = scenario == "direct-image" ? [Attachment(id:"image1",name:"synthetic.png",file:"/synthetic/image.png",bytes:200,width:10,height:10)] : []
                XCTAssertEqual(direct.send(to:try XCTUnwrap(Term(json:core.target)),messageId:"mSynthetic1",text:"Synthetic GUI request",attachments:images),.notSent("시작되지 않음"))
                XCTAssertEqual(directLedger.read("mSynthetic1")?.state,"not_sent")
            }
            XCTAssertEqual(core.sends,1)
            XCTAssertEqual(LiveReplyArchive(url:archiveURL).entries.map { $0["body"] },["Synthetic captured final"])
        }
    }

    func testAttachmentPutFailureAndUnsafeReceiptOwnershipNeverDispatch() throws {
        let folder = try fixture(); let source = folder.appendingPathComponent("unused.jsonl")
        try Data().write(to:source)
        let store = UserDispatchReceipts(root:folder.appendingPathComponent("receipts"))
        let core = Core(source:source); core.putFails = true
        let base = AnswerSender(hc:core,ledger:Ledger(dir:folder.appendingPathComponent("ask")),lockPath:folder.appendingPathComponent("send.lock").path,originReceipts:store)
        let direct = DirectSender(base:base,ledger:Ledger(dir:folder.appendingPathComponent("direct")))
        let image = Attachment(id:"image1",name:"synthetic.png",file:"/synthetic/image.png",bytes:200,width:10,height:10)
        _ = direct.send(to:try XCTUnwrap(Term(json:core.target)),messageId:"mImageFail1",text:"Synthetic image request",attachments:[image])
        XCTAssertEqual(core.sends,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.root.path))
        try FileManager.default.createDirectory(at:store.root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
        _ = direct.send(to:try XCTUnwrap(Term(json:core.target)),messageId:"mUnsafe001",text:"Synthetic request")
        XCTAssertEqual(core.sends,0)
    }
}
