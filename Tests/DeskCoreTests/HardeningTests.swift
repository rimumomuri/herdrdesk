import Foundation
import XCTest
@testable import DeskCore

/// Regressions for long-running failures: a full lineage store, transient hc errors, lock reuse and hc runner races.
final class HardeningTests: XCTestCase {
    let owner = LineageIdentity(address:"t1",session:"800:71",role:"lead")

    func temporary() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }
        return url
    }

    // MARK: lineage

    func testLineageKeepsAcceptingRootsPastTheStorageLimit() throws {
        let store = LineageStore(root:temporary().appendingPathComponent("lineage"))
        let now = Date()
        for i in 0..<520 {
            try store.createRoot(id:String(format:"mFill%04d",i),conversationId:"direct:lead",recipient:owner,
                                 now:now.addingTimeInterval(Double(i)))
        }
        let roots = try store.snapshot().roots
        XCTAssertLessThanOrEqual(roots.count,401)
        XCTAssertTrue(roots.contains { $0.originRequestId == "mFill0519" })
        XCTAssertFalse(roots.contains { $0.originRequestId == "mFill0000" })
    }

    func testExpiredRootIsDroppedWithItsTasksWhenANewRootIsCreated() throws {
        let store = LineageStore(root:temporary().appendingPathComponent("lineage"))
        let start = Date()
        try store.createRoot(id:"mOld0001",conversationId:"direct:lead",recipient:owner,now:start)
        try store.task(id:"old-task",origin:"mOld0001",parent:nil,owner:owner,actor:owner,now:start)
        let later = start.addingTimeInterval(8 * 24 * 3600)
        try store.createRoot(id:"mNew0001",conversationId:"direct:lead",recipient:owner,now:later)
        let state = try store.snapshot()
        XCTAssertEqual(state.roots.map(\.originRequestId),["mNew0001"])
        XCTAssertTrue(state.tasks.isEmpty)
    }

    func testUnexpiredRootsAreKeptBelowTheLimit() {
        var state = LineageSnapshot()
        state.roots = (0..<3).map { LineageRoot(originRequestId:"mKeep000\($0)",conversationId:"room:a",recipient:owner,
                                                createdAt:Double($0),expiresAt:1_000,dispatchId:nil,delivery:"dispatched") }
        state.prune(nowMs:500)
        XCTAssertEqual(state.roots.count,3)
    }

    // MARK: terminal refresh

    func liveStore() -> TerminalStore {
        let store = TerminalStore()
        store.replace(address:"t1",with:["address":"t1","state":"live","created_ms":1,"pid":2])
        return store
    }

    func testTransientGetFailureKeepsTheTerminal() {
        let store = liveStore()
        store.apply(get:HcResult(code:-1,out:"",err:"",timedOut:true),address:"t1")
        XCTAssertNotNil(store.terms["t1"])
        store.apply(get:HcResult(code:1,out:"",err:"connection refused",timedOut:false),address:"t1")
        XCTAssertNotNil(store.terms["t1"])
        store.apply(get:HcResult(code:0,out:"not json",err:"",timedOut:false),address:"t1")
        XCTAssertNotNil(store.terms["t1"])
    }

    func testNotFoundOrFinishedRemovesTheTerminal() {
        let gone = liveStore()
        gone.apply(get:HcResult(code:3,out:"",err:#"{"error":{"kind":"not_found","message":"no terminal"}}"#,timedOut:false),address:"t1")
        XCTAssertNil(gone.terms["t1"])
        let finished = liveStore()
        finished.apply(get:HcResult(code:0,out:#"{"address":"t1","state":"finished"}"#,err:"",timedOut:false),address:"t1")
        XCTAssertNil(finished.terms["t1"])
        let updated = liveStore()
        updated.apply(get:HcResult(code:0,out:#"{"address":"t1","state":"live","turn":7}"#,err:"",timedOut:false),address:"t1")
        XCTAssertEqual(updated.terms["t1"]?.turn,7)
    }

    func testPageSeesWhichTerminalsAreSpawnedWorkersButNotOtherTaskLabels() {
        let store = TerminalStore()
        store.replace(address:"t9",with:["address":"t9","state":"live","created_ms":1,"pid":2,
            "labels":["task.spawned":"1","task.id":"kunkun-000053","secret.token":"x"]])
        let labels = store.terms["t9"]?.publicJSON["labels"] as? [String:String]
        XCTAssertEqual(labels?["task.spawned"],"1")
        XCTAssertNil(labels?["task.id"])
        XCTAssertNil(labels?["secret.token"])
    }

    // MARK: lock and hc runner

    func testFileLockReleaseIsIdempotent() throws {
        let path = temporary().appendingPathComponent("send.lock").path
        let lock = try XCTUnwrap(FileLock.tryAcquire(path:path))
        XCTAssertNil(FileLock.tryAcquire(path:path))
        lock.release(); lock.release()
        XCTAssertFalse(lock.isHeld)
        let again = try XCTUnwrap(FileLock.tryAcquire(path:path))
        lock.release()   // must not unlock or close the new holder's descriptor
        XCTAssertNil(FileLock.tryAcquire(path:path))
        again.release()
    }

    func testMissingExecutableFailsFast() {
        let r = ProcessHc(path:"/nonexistent/hc").run(["ls"],timeout:5)
        XCTAssertEqual(r.code,-1)
        XCTAssertFalse(r.timedOut)
    }

    func testFastExitIsNeverMistakenForATimeout() {
        let runner = ProcessHc(path:"/bin/echo")
        for i in 0..<40 {
            let started = Date()
            let r = runner.run(["hello\(i)"],timeout:5)
            XCTAssertFalse(r.timedOut)
            XCTAssertEqual(r.code,0)
            XCTAssertEqual(r.out,"hello\(i)\n")
            XCTAssertLessThan(Date().timeIntervalSince(started),3)
        }
    }
}
