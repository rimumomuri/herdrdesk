import Foundation
import XCTest
@testable import DeskCore

final class WaitingTargetTests: XCTestCase {
    private final class Core: HcRunning {
        var pid = 71
        var blocked = true
        var linkedSession = "800:71"
        var askState = "open"
        var expired = false
        var duplicate = false
        var calls: [[String]] = []
        func run(_ args: [String], timeout: TimeInterval) -> HcResult {
            calls.append(args)
            let actor: [String:Any] = ["address":"asker","state":"live","created_ms":900,"pid":72,"status":["app":"codex","state":"idle"],
                "labels":["recovery.role":"asker","ask.id":"q20261119085900aabbcc","ask.text":"Registered summary","ask.session":"900:72","ask.state":askState,
                          "ask.approval_role":"worker","ask.approval_session":linkedSession,"ask.expires":expired ? "2000-01-01T00:00:00Z":"2099-01-01T00:00:00Z"]]
            let worker: [String:Any] = ["address":"worker","state":"live","created_ms":800,"pid":pid,"status":["app":"codex","state":blocked ? "blocked":"working"],"labels":["recovery.role":"worker"]]
            let object: [String:Any]
            if args.first == "ls" {
                var second = worker; second["address"] = "duplicate"
                object = ["terminals": args.contains("recovery.role=worker") ? (duplicate ? [worker,second] : [worker]) : [actor]]
            } else { var current = worker; if args.contains("duplicate") { current["address"] = "duplicate" }; object = args.contains("asker") ? actor : current }
            return HcResult(code:0,out:String(data:try! JSONSerialization.data(withJSONObject:object),encoding:.utf8)!,err:"",timedOut:false)
        }
    }
    private func client(_ core: Core) -> AnswerSender {
        AnswerSender(hc:core,ledger:Ledger(dir:URL(fileURLWithPath:"/unused-synthetic-ledger")),lockPath:"/unused-synthetic-lock")
    }
    func testUnknownBlockerRequiresFreshSameSessionAndStillBlocked() {
        let core = Core()
        let request = WaitingTargetRequest(kind:"blocked",actorAddress:"worker",actorSession:"800:71",actorRole:"worker",
            targetAddress:"worker",targetSession:"800:71",targetRole:"worker",requestID:nil)
        XCTAssertEqual(resolveWaitingTarget(request,client:client(core))?.address,"worker")
        core.pid = 73
        XCTAssertNil(resolveWaitingTarget(request,client:client(core)))
        core.pid = 71; core.blocked = false
        XCTAssertNil(resolveWaitingTarget(request,client:client(core)))
        core.blocked = true; core.duplicate = true
        XCTAssertNil(resolveWaitingTarget(request,client:client(core)))
    }
    func testRegisteredLinkIsNotRuntimeApprovalAndCannotOpenRelinkedOrResolvedRequest() {
        let core = Core()
        let request = WaitingTargetRequest(kind:"question",actorAddress:"asker",actorSession:"900:72",actorRole:"asker",
            targetAddress:"worker",targetSession:"800:71",targetRole:"worker",requestID:"q20261119085900aabbcc")
        XCTAssertEqual(resolveWaitingTarget(request,client:client(core))?.session,"800:71")
        core.linkedSession = "800:73"
        XCTAssertNil(resolveWaitingTarget(request,client:client(core)))
        core.linkedSession = "800:71"; core.askState = "acked"
        XCTAssertNil(resolveWaitingTarget(request,client:client(core)))
        core.askState = "open"; core.expired = true
        XCTAssertNil(resolveWaitingTarget(request,client:client(core)))
        XCTAssertTrue(core.calls.allSatisfy { ["get","ls"].contains($0.first ?? "") })
    }
}
