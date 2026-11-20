import Foundation

public struct WaitingTargetRequest {
    public let kind, actorAddress, actorSession, actorRole, targetAddress, targetSession, targetRole: String
    public let requestID: String?
    public init(kind: String, actorAddress: String, actorSession: String, actorRole: String,
                targetAddress: String, targetSession: String, targetRole: String, requestID: String?) {
        self.kind = kind; self.actorAddress = actorAddress; self.actorSession = actorSession; self.actorRole = actorRole
        self.targetAddress = targetAddress; self.targetSession = targetSession; self.targetRole = targetRole; self.requestID = requestID
    }
}

public func resolveWaitingTarget(_ request: WaitingTargetRequest, client: AnswerSender) -> Term? {
    func matches(_ term: Term) -> Bool {
        term.address == request.targetAddress && term.session == request.targetSession && term.state == "live"
            && term.isAgent && term.pid > 0 && (term.role ?? "") == request.targetRole
    }
    if request.kind == "blocked" {
        guard request.actorAddress == request.targetAddress, request.actorSession == request.targetSession else { return nil }
        let term: Term
        if !request.targetRole.isEmpty {
            guard case .success(let current) = client.fetchRole(request.targetRole) else { return nil }
            term = current
        } else {
            let response = client.hc.run(["get","--json",request.targetAddress],timeout:10)
            guard response.code == 0, !response.timedOut, let data = response.out.data(using:.utf8),
                  let row = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let current = Term(json:row) else { return nil }
            term = current
        }
        guard matches(term), term.status == "blocked" else { return nil }
        return term
    }
    guard request.kind == "question", let id = request.requestID,
          case .success(let actor) = client.fetchRole(request.actorRole),
          actor.address == request.actorAddress, actor.session == request.actorSession,
          let question = Question(labels:actor.labels), question.id == id, question.session == actor.session,
          ["open","sending","needs-check","sent"].contains(question.state),
          question.expires.map({ $0 > client.now() }) ?? true else { return nil }
    let target: Term
    if let role = question.approvalRole {
        guard role == request.targetRole, question.approvalSession == request.targetSession,
              case .success(let current) = client.fetchRole(role) else { return nil }
        target = current
    } else {
        guard question.state != "sent" else { return nil }
        target = actor
    }
    guard matches(target), question.state != "sent" || target.status == "blocked",
          question.expires.map({ $0 > client.now() }) ?? true else { return nil }
    return target
}
