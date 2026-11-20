import Foundation

/// One explicit invocation from an existing agent; no daemon, decisions, or new agents.
public enum LineageCommand {
    public static func apply(operation: String, input: [String:Any], caller: String, hc: HcRunning, store: LineageStore) throws -> [String:Any] {
        func text(_ key: String) throws -> String {
            guard let value = input[key] as? String, !value.isEmpty, value.count <= 256 else { throw LineageError.invalid }; return value
        }
        func term(_ address: String) throws -> Term {
            let result = hc.run(["get","--json",address],timeout:10)
            guard result.code == 0, !result.timedOut, let bytes = result.out.data(using:.utf8),
                  let row = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any], let term = Term(json:row),
                  term.state == "live", term.isAgent, term.pid > 0, term.address == address else { throw LineageError.ownership }
            return term
        }
        let current = try term(caller), actor = LineageIdentity(current)
        switch operation {
        case "task":
            let owner: LineageIdentity
            if let raw = input["owner"] {
                owner = try JSONDecoder().decode(LineageIdentity.self,from:JSONSerialization.data(withJSONObject:raw))
                guard LineageIdentity(try term(owner.address)) == owner else { throw LineageError.mismatch }
            } else { owner = actor }
            try store.task(id:text("taskId"),origin:text("originRequestId"),parent:input["parentTaskId"] as? String,owner:owner,actor:actor,expiresAt:input["expiresAt"] as? Double)
        case "edge":
            try store.edge(id:text("edgeId"),origin:text("originRequestId"),parent:text("parentTaskId"),child:text("childTaskId"),actor:actor)
        case "delegate":
            guard let body = input["text"] as? String else { throw LineageError.invalid }
            guard let edge = try store.snapshot().edges.first(where: { $0.id == (try? text("edgeId")) }), edge.originRequestId == (try text("originRequestId")) else { throw LineageError.mismatch }
            _ = try store.delegate(id:text("edgeId"),actor:actor,text:body,hc:hc)
        case "accept", "complete":
            guard let task = try store.snapshot().tasks.first(where: { $0.id == (try? text("taskId")) }), task.originRequestId == (try text("originRequestId")) else { throw LineageError.mismatch }
            try store.taskStep(id:text("taskId"),actor:actor,complete:operation == "complete")
        case "pending":
            let taskId = try text("taskId"), requestId = try text("requestId")
            guard let question = Question(labels:current.labels), question.id == requestId, question.session == actor.session,
                  ["open","sending","needs-check","sent"].contains(question.state), question.expires.map({ $0 > Date() }) ?? true,
                  let task = try store.snapshot().tasks.first(where: { $0.id == taskId }) else { throw LineageError.mismatch }
            guard task.originRequestId == (try text("originRequestId")) else { throw LineageError.mismatch }
            let target: LineageIdentity
            if let role = question.approvalRole {
                let client = AnswerSender(hc:hc,ledger:Ledger(dir:store.root.appendingPathComponent("unused")),lockPath:store.root.appendingPathComponent("unused.lock").path)
                guard case .success(let bound) = client.fetchRole(role), bound.session == question.approvalSession else { throw LineageError.mismatch }
                target = LineageIdentity(bound)
            } else { target = actor }
            try store.pending(id:text("pendingId"),taskId:taskId,requestId:requestId,actor:actor,target:target,
                              expiresAt:min(task.expiresAt,question.expires.map { $0.timeIntervalSince1970 * 1000 } ?? task.expiresAt))
        default: throw LineageError.invalid
        }
        let revision = try store.snapshot().revision
        let wake = hc.run(["label",actor.address,"lineage.revision=\(revision)"],timeout:10)
        return ["recorded":true,"revision":revision,"inventoryNotified":wake.code == 0 && !wake.timedOut]
    }
}
