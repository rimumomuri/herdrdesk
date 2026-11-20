import Foundation
import XCTest
@testable import DeskCore

final class LineageTests: XCTestCase {
    final class Core: HcRunning {
        var calls:[[String]]=[]
        var stale=false
        var question=false
        func run(_ args:[String],timeout:TimeInterval)->HcResult {
            calls.append(args)
            if args.first == "ls" { return HcResult(code:0,out:"{\"terminals\":[{\"address\":\"\(args.last?.contains("worker") == true ? "t2":"t1")\"}]}",err:"",timedOut:false) }
            let address=args.last ?? "t1"
            let ask=question&&address == "t1" ? ",\"ask.id\":\"q20261119200000aabbcc\",\"ask.text\":\"Synthetic question\",\"ask.session\":\"800:71\",\"ask.state\":\"open\",\"ask.approval_role\":\"worker\",\"ask.approval_session\":\"900:72\"" : ""
            let output=args.first == "get" ? "{\"address\":\"\(address)\",\"state\":\"live\",\"created_ms\":\(address == "t2" ? 900:800),\"pid\":\(stale ? 99:address == "t2" ? 72:71),\"labels\":{\"recovery.role\":\"\(address == "t2" ? "worker":"lead")\"\(ask)},\"status\":{\"app\":\"codex\",\"state\":\"idle\"}}" : "{\"started\":true,\"turn\":1}"
            return HcResult(code:0,out:output,err:"",timedOut:false)
        }
    }
    let owner = LineageIdentity(address:"t1",session:"800:71",role:"lead")
    let child = LineageIdentity(address:"t2",session:"900:72",role:"worker")
    func store() -> LineageStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }
        return LineageStore(root:url.appendingPathComponent("lineage"))
    }
    func testRootIsUniqueAndChildMustHaveExplicitSameRootParentAndOwner() throws {
        let store = store()
        try store.createRoot(id:"mRoot001",conversationId:"room:one",recipient:owner)
        XCTAssertEqual(try store.snapshot().roots.count,1)
        XCTAssertThrowsError(try store.createRoot(id:"mRoot001",conversationId:"room:two",recipient:owner))
        try store.task(id:"root-task",origin:"mRoot001",parent:nil,owner:owner,actor:owner)
        try store.task(id:"child-task",origin:"mRoot001",parent:"root-task",owner:child,actor:owner)
        try store.edge(id:"edge-one",origin:"mRoot001",parent:"root-task",child:"child-task",actor:owner)
        XCTAssertEqual(try store.snapshot().edges.first?.delivery,"intent")
        XCTAssertNil(try store.snapshot().tasks.last?.acceptedAt)
        XCTAssertThrowsError(try store.task(id:"forged",origin:"mRoot001",parent:"root-task",owner:child,actor:child))
        XCTAssertThrowsError(try store.task(id:"cycle",origin:"mRoot001",parent:"cycle",owner:owner,actor:owner))
        try store.createRoot(id:"mRoot002",conversationId:"room:two",recipient:owner)
        XCTAssertThrowsError(try store.task(id:"cross",origin:"mRoot002",parent:"root-task",owner:child,actor:owner))
    }
    func testDelegationRegistrationDispatchAcceptanceAndCompletionRemainSeparate() throws {
        let store=store(),hc=Core()
        try store.createRoot(id:"mRoot001",conversationId:"room:one",recipient:owner)
        try store.task(id:"root",origin:"mRoot001",parent:nil,owner:owner,actor:owner)
        try store.task(id:"child",origin:"mRoot001",parent:"root",owner:child,actor:owner)
        try store.edge(id:"edge",origin:"mRoot001",parent:"root",child:"child",actor:owner)
        XCTAssertThrowsError(try store.taskStep(id:"child",actor:child,complete:false))
        hc.stale=true
        XCTAssertThrowsError(try store.delegate(id:"edge",actor:owner,text:"synthetic private body",hc:hc))
        XCTAssertFalse(hc.calls.contains{$0.first == "send"})
        hc.stale=false
        XCTAssertEqual(try store.delegate(id:"edge",actor:owner,text:"synthetic private body",hc:hc),"dispatched")
        XCTAssertNil(try store.snapshot().tasks.last?.acceptedAt)
        XCTAssertThrowsError(try store.taskStep(id:"child",actor:owner,complete:false))
        XCTAssertThrowsError(try store.taskStep(id:"child",actor:child,complete:true))
        try store.taskStep(id:"child",actor:child,complete:false)
        try store.taskStep(id:"child",actor:child,complete:true)
        XCTAssertNotNil(try store.snapshot().edges.first?.completedAt)
        XCTAssertThrowsError(try store.delegate(id:"edge",actor:owner,text:"again",hc:hc))
        XCTAssertEqual(hc.calls.filter{$0.first == "send"}.count,1)
        XCTAssertFalse(try String(contentsOf:store.root.appendingPathComponent("state.json"),encoding:.utf8).contains("synthetic private body"))
    }
    func testExpiryDepthAndExplicitPendingContinuation() throws {
        let store=store(),now=Date(),expiry=now.timeIntervalSince1970*1000+60000
        try store.createRoot(id:"mRoot001",conversationId:"direct:lead",recipient:owner,now:now)
        try store.task(id:"root",origin:"mRoot001",parent:nil,owner:owner,actor:owner,expiresAt:expiry,now:now)
        XCTAssertThrowsError(try store.task(id:"expired",origin:"mRoot001",parent:"root",owner:owner,actor:owner,expiresAt:expiry+1,now:now))
        var parent="root"
        for i in 1...15 { let id="d\(i)";try store.task(id:id,origin:"mRoot001",parent:parent,owner:owner,actor:owner,now:now);parent=id }
        XCTAssertThrowsError(try store.task(id:"too-deep",origin:"mRoot001",parent:parent,owner:owner,actor:owner,now:now))
        let q="q20261119200000aabbcc"
        XCTAssertNil(try store.continuationHeader(requestId:q,requester:owner,target:child,now:now))
        try store.pending(id:"pending",taskId:"root",requestId:q,actor:owner,target:child,expiresAt:expiry,now:now)
        XCTAssertThrowsError(try store.pending(id:"duplicate",taskId:"root",requestId:q,actor:owner,target:child,expiresAt:expiry,now:now))
        XCTAssertTrue(store.validatesPending(id:"pending",taskId:"root",origin:"mRoot001",conversation:"direct:lead",requestId:q,requester:owner,target:child,now:now))
        XCTAssertFalse(store.validatesPending(id:"pending",taskId:"root",origin:"mRoot001",conversation:"room:other",requestId:q,requester:owner,target:child,now:now))
        XCTAssertNotNil(try store.continuationHeader(requestId:q,requester:owner,target:child,now:now))
        XCTAssertNil(try store.continuationHeader(requestId:q,requester:owner,target:owner,now:now))
        XCTAssertThrowsError(try store.taskStep(id:"root",actor:owner,complete:false,now:now.addingTimeInterval(61)))
    }
    func testNewDirectPersistsExactOriginAndNeverCreatesDuplicateRoot() throws {
        let store=store(),hc=Core()
        let fixture=store.root.deletingLastPathComponent()
        let base=AnswerSender(hc:hc,ledger:Ledger(dir:fixture.appendingPathComponent("ask")),lockPath:fixture.appendingPathComponent("send.lock").path,lineage:store)
        let sender=DirectSender(base:base,ledger:Ledger(dir:fixture.appendingPathComponent("direct")))
        let term=try XCTUnwrap(Term(json:["address":"t1","state":"live","created_ms":800,"pid":71,"labels":["recovery.role":"lead"],"status":["app":"codex","state":"idle"]]))
        XCTAssertEqual(sender.send(to:term,messageId:"mRoot001",text:"synthetic",conversationId:"direct:lead"),.sent(turn:1))
        XCTAssertEqual(try store.snapshot().roots.first?.conversationId,"direct:lead")
        XCTAssertEqual(try store.snapshot().roots.first?.recipient,owner)
        XCTAssertEqual(try store.snapshot().roots.first?.delivery,"dispatched")
        XCTAssertEqual(sender.send(to:term,messageId:"mRoot001",text:"synthetic",conversationId:"room:other"),.refused(.alreadyHandled("sent")))
        XCTAssertEqual(try store.snapshot().roots.count,1)
        XCTAssertTrue(try XCTUnwrap(hc.calls.first{$0.first == "send"}?.last).contains("mRoot001"))
    }
    func testHelperVerifiesCurrentCallerAndQuestionAndAnswerOnlyContinuesCompleteLink() throws {
        let store=store(),hc=Core(),q="q20261119200000aabbcc"
        try store.createRoot(id:"mRoot001",conversationId:"direct:lead",recipient:owner)
        let input:[String:Any]=["taskId":"root","originRequestId":"mRoot001"]
        hc.stale=true
        XCTAssertThrowsError(try LineageCommand.apply(operation:"task",input:input,caller:"t1",hc:hc,store:store))
        hc.stale=false
        _ = try LineageCommand.apply(operation:"task",input:input,caller:"t1",hc:hc,store:store)
        let pending:[String:Any]=["pendingId":"pending","taskId":"root","requestId":q,"originRequestId":"mRoot001"]
        XCTAssertThrowsError(try LineageCommand.apply(operation:"pending",input:pending,caller:"t1",hc:hc,store:store))
        hc.question=true
        _ = try LineageCommand.apply(operation:"pending",input:pending,caller:"t1",hc:hc,store:store)
        let fixture=store.root.deletingLastPathComponent()
        let linked=AnswerSender(hc:hc,ledger:Ledger(dir:fixture.appendingPathComponent("answer-one")),lockPath:fixture.appendingPathComponent("one.lock").path,lineage:store)
        XCTAssertEqual(linked.send(role:"lead",questionId:q,text:"Synthetic answer"),.sent(turn:1))
        XCTAssertTrue(try XCTUnwrap(hc.calls.last{$0.first == "send"}?.last).contains("mRoot001"))
        let unlinked=AnswerSender(hc:hc,ledger:Ledger(dir:fixture.appendingPathComponent("answer-two")),lockPath:fixture.appendingPathComponent("two.lock").path,lineage:self.store())
        XCTAssertEqual(unlinked.send(role:"lead",questionId:q,text:"Synthetic answer"),.sent(turn:1))
        XCTAssertFalse(try XCTUnwrap(hc.calls.last{$0.first == "send"}?.last).contains("HerdrDesk lineage"))
    }
}
