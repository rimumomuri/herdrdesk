import Foundation
import CryptoKit
import Darwin

public struct LineageIdentity: Codable, Equatable {
    public var address, session, role: String
    public init(_ term: Term) { address = term.address; session = term.session; role = term.role ?? "" }
    public init(address: String, session: String, role: String = "") { self.address = address; self.session = session; self.role = role }
}
public struct LineageRoot: Codable {
    public var originRequestId, conversationId: String
    public var recipient: LineageIdentity
    public var createdAt, expiresAt: Double
    public var dispatchId: String?
    public var delivery: String
}
public struct LineageTask: Codable {
    public var id, originRequestId: String
    public var parentTaskId: String?
    public var owner: LineageIdentity
    public var expiresAt: Double
    public var acceptedAt, completedAt: Double?
}
public struct LineageEdge: Codable {
    public var id, originRequestId, parentTaskId, childTaskId, delivery: String
    public var from, to: LineageIdentity
    public var acceptedAt, completedAt: Double?
}
public struct LineagePendingLink: Codable {
    public var id, kind, originRequestId, taskId, requestId: String
    public var requester, target: LineageIdentity
    public var expiresAt: Double
}
public struct LineageSnapshot: Codable {
    public var revision = 0
    public var roots: [LineageRoot] = []
    public var tasks: [LineageTask] = []
    public var edges: [LineageEdge] = []
    public var pendingLinks: [LineagePendingLink] = []

    /// Drops records that can no longer be used, so the store never fills up and refuses new sends.
    /// Expired roots go with every task, edge and link of theirs; expired links go on their own.
    /// If live roots still exceed `maxRoots`, the oldest are dropped (with their dependents).
    public mutating func prune(nowMs: Double, maxRoots: Int = 400) {
        var keep = Set(roots.filter { $0.expiresAt > nowMs }.map(\.originRequestId))
        if keep.count > maxRoots {
            let newest = roots.filter { keep.contains($0.originRequestId) }
                .sorted { $0.createdAt > $1.createdAt }.prefix(maxRoots).map(\.originRequestId)
            keep = Set(newest)
        }
        roots.removeAll { !keep.contains($0.originRequestId) }
        tasks.removeAll { !keep.contains($0.originRequestId) }
        edges.removeAll { !keep.contains($0.originRequestId) }
        pendingLinks.removeAll { !keep.contains($0.originRequestId) || $0.expiresAt <= nowMs }
    }
}
public enum LineageError: String, Error { case invalid, missing, mismatch, duplicate, expired, ownership, cycle, depth, transition, storage }

public final class LineageStore {
    public let root: URL
    private let mutex = NSLock()
    public init(root: URL) { self.root = root }
    public static func defaultRoot() -> URL { DeskPaths.data.appendingPathComponent("lineage",isDirectory:true) }
    public func snapshot() throws -> LineageSnapshot {
        if !FileManager.default.fileExists(atPath:root.path) { return LineageSnapshot() }
        return try locked { try read() }
    }
    public func publicJSON() -> [String:Any] {
        guard let snapshot = try? snapshot(), let data = try? JSONEncoder().encode(snapshot),
              let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return ["unavailable":true] }
        return object
    }
    public func createRoot(id: String, conversationId: String, recipient: LineageIdentity, now: Date = Date()) throws {
        guard id.range(of:#"\Am[A-Za-z0-9_-]{6,60}\z"#,options:.regularExpression) != nil,
              conversationId.count <= 256,
              (conversationId.hasPrefix("room:") && conversationId.count > 5) || (conversationId.hasPrefix("direct:") && conversationId.count > 7),
              !conversationId.unicodeScalars.contains(where: { $0.value < 32 }), valid(recipient) else { throw LineageError.invalid }
        try change { state in
            guard !state.roots.contains(where: { $0.originRequestId == id }) else { throw LineageError.duplicate }
            state.prune(nowMs: ms(now))   // every send adds a root: without this the store fills and refuses all sends
            state.roots.append(LineageRoot(originRequestId:id,conversationId:conversationId,recipient:recipient,createdAt:ms(now),expiresAt:ms(now)+604800000,dispatchId:nil,delivery:"intent"))
        }
    }
    public func rootDelivery(id: String, dispatchId: String?, outcome: SendOutcome) throws {
        try change { state in
            guard let i = state.roots.firstIndex(where: { $0.originRequestId == id }) else { throw LineageError.missing }
            if let dispatchId { state.roots[i].dispatchId = dispatchId }
            state.roots[i].delivery = delivery(outcome)
        }
    }
    public func task(id: String, origin: String, parent: String?, owner: LineageIdentity, actor: LineageIdentity, expiresAt: Double? = nil, now: Date = Date()) throws {
        guard validID(id), valid(owner), valid(actor) else { throw LineageError.invalid }
        try change { state in
            let root = try checkedRoot(origin,state,now)
            guard !state.tasks.contains(where: { $0.id == id }) else { throw LineageError.duplicate }
            var limit = root.expiresAt, cursor = parent, seen = Set([id]), depth = 1
            if let parent {
                let task = try checkedTask(parent,state,now)
                guard task.originRequestId == origin else { throw LineageError.mismatch }
                guard task.owner == actor else { throw LineageError.ownership }
                guard task.completedAt == nil else { throw LineageError.transition }
                limit = min(limit,task.expiresAt)
            } else if owner != root.recipient || actor != root.recipient { throw LineageError.ownership }
            while let key = cursor {
                guard seen.insert(key).inserted else { throw LineageError.cycle }
                depth += 1; guard depth <= 16 else { throw LineageError.depth }
                let task = try checkedTask(key,state,now)
                guard task.originRequestId == origin else { throw LineageError.mismatch }
                cursor = task.parentTaskId
            }
            let expires = expiresAt ?? limit
            guard expires.isFinite, expires > ms(now), expires <= limit else { throw LineageError.expired }
            state.tasks.append(LineageTask(id:id,originRequestId:origin,parentTaskId:parent,owner:owner,expiresAt:expires,acceptedAt:nil,completedAt:nil))
        }
    }
    public func edge(id: String, origin: String, parent: String, child: String, actor: LineageIdentity, now: Date = Date()) throws {
        guard validID(id) else { throw LineageError.invalid }
        try change { state in
            _ = try checkedRoot(origin,state,now)
            let from = try checkedTask(parent,state,now), to = try checkedTask(child,state,now)
            guard from.originRequestId == origin, to.originRequestId == origin, to.parentTaskId == parent else { throw LineageError.mismatch }
            guard from.owner == actor else { throw LineageError.ownership }
            guard from.completedAt == nil, to.completedAt == nil else { throw LineageError.transition }
            guard !state.edges.contains(where: { $0.id == id || $0.childTaskId == child }) else { throw LineageError.duplicate }
            state.edges.append(LineageEdge(id:id,originRequestId:origin,parentTaskId:parent,childTaskId:child,delivery:"intent",from:from.owner,to:to.owner,acceptedAt:nil,completedAt:nil))
        }
    }
    public func taskStep(id: String, actor: LineageIdentity, complete: Bool, now: Date = Date()) throws {
        try change { state in
            let task = try checkedTask(id,state,now)
            _ = try checkedRoot(task.originRequestId,state,now)
            guard task.owner == actor else { throw LineageError.ownership }
            guard task.completedAt == nil else { throw LineageError.transition }
            let i = state.tasks.firstIndex(where: { $0.id == id })!
            let edge = state.edges.firstIndex(where: { $0.childTaskId == id })
            if task.parentTaskId != nil {
                guard let edge, state.edges[edge].delivery != "intent" else { throw LineageError.transition }
            }
            if complete {
                guard task.acceptedAt != nil, task.completedAt == nil else { throw LineageError.transition }
                state.tasks[i].completedAt = ms(now)
                if let edge { state.edges[edge].completedAt = ms(now) }
            } else {
                guard task.acceptedAt == nil else { throw LineageError.duplicate }
                state.tasks[i].acceptedAt = ms(now)
                if let edge { state.edges[edge].acceptedAt = ms(now) }
            }
        }
    }
    public func pending(id: String, taskId: String, requestId: String, actor: LineageIdentity, target: LineageIdentity, expiresAt: Double, now: Date = Date()) throws {
        guard validID(id), requestId.range(of:"^q[0-9]{14}[0-9a-f]{6}$",options:.regularExpression) != nil, valid(target) else { throw LineageError.invalid }
        try change { state in
            let task = try checkedTask(taskId,state,now)
            _ = try checkedRoot(task.originRequestId,state,now)
            guard task.owner == actor else { throw LineageError.ownership }
            guard expiresAt.isFinite, expiresAt > ms(now), expiresAt <= task.expiresAt else { throw LineageError.expired }
            guard task.completedAt == nil else { throw LineageError.transition }
            guard !state.pendingLinks.contains(where: { $0.id == id || ($0.requestId == requestId && $0.requester == actor) }) else { throw LineageError.duplicate }
            state.pendingLinks.append(LineagePendingLink(id:id,kind:"manualAsk",originRequestId:task.originRequestId,taskId:taskId,requestId:requestId,requester:actor,target:target,expiresAt:expiresAt))
        }
    }
    public func delegate(id: String, actor: LineageIdentity, text: String, hc: HcRunning, now: Date = Date()) throws -> String {
        guard checkText(text) == nil else { throw LineageError.invalid }
        let first = try snapshot()
        guard let edge = first.edges.first(where: { $0.id == id }), edge.from == actor else { throw LineageError.ownership }
        let current = hc.run(["get","--json",edge.to.address],timeout:10)
        guard current.code == 0, !current.timedOut, let bytes = current.out.data(using:.utf8),
              let object = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any], let term = Term(json:object),
              term.state == "live", term.isAgent, LineageIdentity(term) == edge.to else { throw LineageError.mismatch }
        let root = try checkedRoot(edge.originRequestId,first,now)
        let header: [String:Any] = ["originRequestId":root.originRequestId,"conversationId":root.conversationId,"taskId":edge.childTaskId,"parentTaskId":edge.parentTaskId,"edgeId":edge.id]
        let payload = "[HerdrDesk lineage " + String(data:try JSONSerialization.data(withJSONObject:header,options:.sortedKeys),encoding:.utf8)! + "]\n" + text
        try change { state in
            let child = try checkedTask(edge.childTaskId,state,now), parent = try checkedTask(edge.parentTaskId,state,now)
            guard child.completedAt == nil, parent.completedAt == nil else { throw LineageError.transition }
            guard let i = state.edges.firstIndex(where: { $0.id == id }), state.edges[i].delivery == "intent", state.edges[i].from == actor else { throw LineageError.transition }
            state.edges[i].delivery = "dispatching"
        }
        let outcome = AnswerSender.interpret(hc.run(["send","--json",edge.to.address,payload],timeout:90))
        let result = delivery(outcome)
        try change { state in
            guard let i = state.edges.firstIndex(where: { $0.id == id }) else { throw LineageError.missing }
            state.edges[i].delivery = result
        }
        return result
    }
    public static func originHeader(id: String, conversationId: String) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject:["originRequestId":id,"conversationId":conversationId],options:.sortedKeys)
        return "[HerdrDesk lineage " + String(data:bytes,encoding:.utf8)! + "]\n"
    }
    public func continuationHeader(requestId: String, requester: LineageIdentity, target: LineageIdentity, now: Date = Date()) throws -> String? {
        let state = try snapshot()
        let links = state.pendingLinks.filter { $0.kind == "manualAsk" && $0.requestId == requestId && $0.requester == requester && $0.target == target && $0.expiresAt > ms(now) }
        guard links.count == 1, let link = links.first else { return nil }
        let task = try checkedTask(link.taskId,state,now), root = try checkedRoot(link.originRequestId,state,now)
        guard task.originRequestId == root.originRequestId, task.owner == requester, task.completedAt == nil else { return nil }
        let data = try JSONSerialization.data(withJSONObject:["originRequestId":root.originRequestId,"conversationId":root.conversationId,"taskId":task.id,"pendingId":link.id,"requestId":requestId],options:.sortedKeys)
        return "[HerdrDesk lineage " + String(data:data,encoding:.utf8)! + "]\n"
    }
    public func validatesPending(id: String, taskId: String, origin: String, conversation: String, requestId: String, requester: LineageIdentity, target: LineageIdentity, now: Date = Date()) -> Bool {
        guard let state = try? snapshot(), let root = try? checkedRoot(origin,state,now), root.conversationId == conversation,
              let task = try? checkedTask(taskId,state,now), task.originRequestId == origin, task.owner == requester,
              task.completedAt == nil else { return false }
        return state.pendingLinks.filter { $0.id == id && $0.kind == "manualAsk" && $0.taskId == taskId && $0.originRequestId == origin && $0.requestId == requestId && $0.requester == requester && $0.target == target && $0.expiresAt > ms(now) }.count == 1
    }
    private func checkedRoot(_ id: String, _ state: LineageSnapshot, _ now: Date) throws -> LineageRoot {
        guard let root = state.roots.first(where: { $0.originRequestId == id }) else { throw LineageError.missing }
        guard root.expiresAt > ms(now) else { throw LineageError.expired }; return root
    }
    private func checkedTask(_ id: String, _ state: LineageSnapshot, _ now: Date) throws -> LineageTask {
        guard let task = state.tasks.first(where: { $0.id == id }) else { throw LineageError.missing }
        guard task.expiresAt > ms(now) else { throw LineageError.expired }; return task
    }
    private func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }
    private func validID(_ value: String) -> Bool { value.range(of:#"\A[A-Za-z0-9][A-Za-z0-9._-]{0,95}\z"#,options:.regularExpression) != nil }
    private func valid(_ value: LineageIdentity) -> Bool {
        !value.address.isEmpty && value.address.count <= 160 && !value.address.hasPrefix("-")
            && value.address.range(of:#"\A[A-Za-z0-9._/-]+\z"#,options:.regularExpression) != nil
            && value.session.range(of:#"\A[1-9][0-9]*:[1-9][0-9]*\z"#,options:.regularExpression) != nil
            && (value.role.isEmpty || value.role.range(of:#"\A[A-Za-z0-9._-]{1,64}\z"#,options:.regularExpression) != nil)
    }
    private func delivery(_ outcome: SendOutcome) -> String {
        switch outcome { case .sent:return "dispatched"; case .notSent:return "not_sent"; case .needsCheck:return "needs_check"; case .refused:return "not_sent" }
    }
    private func change(_ action: (inout LineageSnapshot) throws -> Void) throws {
        try locked {
            var state = try read(); try action(&state)
            guard state.roots.count <= 500, state.tasks.count <= 4000, state.edges.count <= 4000, state.pendingLinks.count <= 4000 else { throw LineageError.storage }
            state.revision += 1
            let data = try JSONEncoder().encode(state)
            guard data.count < 2 * 1024 * 1024 else { throw LineageError.storage }
            let url = root.appendingPathComponent("state.json")
            let temporary = root.appendingPathComponent("." + UUID().uuidString)
            let fd = open(temporary.path,O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,0o600)
            guard fd >= 0 else { throw LineageError.storage }
            let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
            do {
                try handle.write(contentsOf:data); try handle.synchronize(); try handle.close()
                guard rename(temporary.path,url.path) == 0 else { throw LineageError.storage }
            } catch { try? handle.close(); unlink(temporary.path); throw error }
        }
    }
    private func read() throws -> LineageSnapshot {
        let url = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath:url.path) else { return LineageSnapshot() }
        try privateItem(url,directory:false)
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 2 * 1024 * 1024 else { throw LineageError.storage }
        return try JSONDecoder().decode(LineageSnapshot.self,from:Data(contentsOf:url))
    }
    private func privateItem(_ url: URL, directory: Bool) throws {
        let a = try FileManager.default.attributesOfItem(atPath:url.path)
        guard a[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular),
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(), (a[.posixPermissions] as? NSNumber)?.intValue == (directory ? 0o700:0o600) else { throw LineageError.storage }
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        mutex.lock(); defer { mutex.unlock() }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try privateItem(root,directory:true)
        let fd = open(root.appendingPathComponent("write.lock").path,O_CREAT | O_RDWR | O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw LineageError.storage }; defer { close(fd) }
        guard flock(fd,LOCK_EX) == 0 else { throw LineageError.storage }; defer { flock(fd,LOCK_UN) }
        return try action()
    }
}
