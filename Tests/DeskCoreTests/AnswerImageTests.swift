import Foundation
import XCTest
@testable import DeskCore

/// Answering a registered question with images: files go beside the asker with hc put first, then one answer names them.
final class AnswerImageTests: XCTestCase {
    class FakeHc: HcRunning {
        var calls: [[String]] = []
        var putFails = false
        var target: [String: Any] = ["address":"t1","state":"live","pid":71,"created_ms":800,
            "status":["app":"codex","state":"idle"],
            "labels":["recovery.role":"asker","ask.id":"qImage0001","ask.text":"Which screen?","ask.session":"800:71"]]
        func run(_ args: [String], timeout: TimeInterval) -> HcResult {
            calls.append(args)
            var object: [String: Any] = [:]
            switch args.first {
            case "get": object = target
            case "ls": object = ["terminals":[target]]
            case "put": if putFails { return HcResult(code:1,out:"",err:"no space",timedOut:false) }; object = ["path":"/remote/landed-\(calls.count).png"]
            case "send": object = ["started":true,"turn":4]
            case "label":   // like Core: labels change what the next get returns
                var labels = target["labels"] as! [String: Any]
                for pair in args.dropFirst(2) { let kv = pair.split(separator: "=", maxSplits: 1).map(String.init); if kv.count == 2 { labels[kv[0]] = kv[1] } }
                target["labels"] = labels
            default: break
            }
            return HcResult(code:0,out:String(data:try! JSONSerialization.data(withJSONObject:object),encoding:.utf8)!,err:"",timedOut:false)
        }
        var sent: String? { calls.first { $0.first == "send" }?.last }
    }

    func sender(_ hc: FakeHc) throws -> (AnswerSender, Ledger) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("answer-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ledger = Ledger(dir: dir.appendingPathComponent("ledger"))
        return (AnswerSender(hc: hc, ledger: ledger, lockPath: dir.appendingPathComponent("send.lock").path), ledger)
    }
    let image = Attachment(id:"img1",name:"screen.png",file:"/drafts/screen.png",bytes:4096,width:640,height:480)

    func testAnswerWithAnImagePutsItFirstAndNamesItsPath() throws {
        let hc = FakeHc(); let (s, ledger) = try sender(hc)
        XCTAssertEqual(s.send(role:"asker", questionId:"qImage0001", text:"This one", attachments:[image]), .sent(turn: 4))
        let order = hc.calls.map { $0.first ?? "" }.filter { ["put","send"].contains($0) }
        XCTAssertEqual(order, ["put","send"])
        XCTAssertEqual(hc.calls.first { $0.first == "put" }, ["put","--json","t1","/drafts/screen.png"])
        let body = try XCTUnwrap(hc.sent)
        XCTAssertTrue(body.contains("[User reply · Question qImage0001 · HerdrDesk]\nThis one"), body)
        XCTAssertTrue(body.contains("/remote/landed-"), body)
        XCTAssertTrue(body.contains("640×480"), body)
        XCTAssertEqual(ledger.read("qImage0001")?.state, "sent")
    }

    func testAnImageAloneIsAnAnswer() throws {
        let hc = FakeHc(); let (s, _) = try sender(hc)
        XCTAssertEqual(s.send(role:"asker", questionId:"qImage0001", text:"  ", attachments:[image]), .sent(turn: 4))
        XCTAssertEqual(s.send(role:"asker", questionId:"qImage0001", text:"", attachments:[]), .refused(.emptyText))
    }

    func testFailedPutSendsNothingAndKeepsTheQuestionOpen() throws {
        let hc = FakeHc(); hc.putFails = true; let (s, ledger) = try sender(hc)
        guard case .notSent = s.send(role:"asker", questionId:"qImage0001", text:"This one", attachments:[image]) else { return XCTFail("expected notSent") }
        XCTAssertNil(hc.sent)
        XCTAssertEqual(ledger.read("qImage0001")?.state, "not_sent")
        XCTAssertTrue(hc.calls.contains(["label","t1","ask.state=open"]))
    }

    func testAnotherQuestionDuringTheCopySendsNothing() throws {
        let hc = SwapHc(); let (s, ledger) = try sender(hc)
        guard case .notSent = s.send(role:"asker", questionId:"qImage0001", text:"This one", attachments:[image]) else { return XCTFail("expected notSent") }
        XCTAssertNil(hc.sent)
        XCTAssertEqual(ledger.read("qImage0001")?.note, "question changed during image transfer")
    }

    /// After the first put the asker shows a different question.
    final class SwapHc: FakeHc {
        override func run(_ args: [String], timeout: TimeInterval) -> HcResult {
            if args.first == "get", calls.contains(where: { $0.first == "put" }) {
                var labels = target["labels"] as! [String: Any]; labels["ask.id"] = "qOther00001"; target["labels"] = labels
            }
            return super.run(args, timeout: timeout)
        }
    }

    func testTooManyImagesAreRefused() throws {
        let hc = FakeHc(); let (s, _) = try sender(hc)
        let many = (0...AttachmentStore.maxCount).map { Attachment(id:"i\($0)",name:"\($0).png",file:"/d/\($0).png",bytes:1,width:1,height:1) }
        XCTAssertEqual(s.send(role:"asker", questionId:"qImage0001", text:"x", attachments:many), .refused(.badText))
        XCTAssertTrue(hc.calls.isEmpty)
    }
}
