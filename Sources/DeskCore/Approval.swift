import Foundation

/// "Open the terminal awaiting approval" for an explicitly linked question. Moving the view only:
/// nothing here approves, sends keys or runs anything. The page gives a question id and nothing else.
public enum ApprovalRefusal: Error, Equatable, CustomStringConvertible {
    case noQuestion, duplicateQuestion, noLink, closed(String), askerSessionChanged, expired
    case target(ResolveError), targetSessionChanged, notLive

    public var description: String {
        switch self {
        case .noQuestion: return "이 질문을 찾지 못했어요."
        case .duplicateQuestion: return "같은 질문 번호가 둘 이상이라 열지 않았어요."
        case .noLink: return "이 질문에는 승인 대상이 연결돼 있지 않아요."
        case .closed(let s): return "이 질문은 이미 '\(s)' 상태라 열지 않았어요."
        case .askerSessionChanged: return "질문한 총괄의 세션이 바뀌어 열지 않았어요."
        case .expired: return "질문 기한이 지나 열지 않았어요."
        case .target(.missing): return "승인 대상 담당이 지금 실행 중이 아니에요."
        case .target(.ambiguous): return "승인 대상 담당이 둘 이상 실행 중이라 열지 않았어요."
        case .target(.notAgent): return "승인 대상이 AI가 아닌 셸이라 열지 않았어요."
        case .targetSessionChanged: return "승인 대상 터미널이 재시작·교체돼(세션 변경) 열지 않았어요."
        case .notLive: return "Herdr 실시간 연결이 끊겨 있어 열지 않았어요."
        }
    }
}

/// States in which the linked target may still be opened (acked / withdrawn questions are over).
public let approvalActiveStates: Set<String> = ["open", "sending", "needs-check", "sent"]

/// The one live AI terminal that currently carries this question id (two → refused).
public func askerOf(questionId: String, in terms: [Term]) -> Result<Term, ApprovalRefusal> {
    let hits = terms.filter { $0.state == "live" && $0.isAgent && $0.labels["ask.id"] == questionId }
    if hits.count > 1 { return .failure(.duplicateQuestion) }
    guard let t = hits.first else { return .failure(.noQuestion) }
    return .success(t)
}

/// Pure check on fresh reads. The asker's own status (working / blocked on a permission) is deliberately
/// NOT checked: opening another terminal is allowed even while the asker itself is blocked.
public func checkApproval(questionId: String, asker: Term, target: Result<Term, ResolveError>, now: Date = Date()) -> Result<Term, ApprovalRefusal> {
    guard asker.state == "live", asker.isAgent, let q = Question(labels: asker.labels), q.id == questionId else { return .failure(.noQuestion) }
    guard approvalActiveStates.contains(q.state) else { return .failure(.closed(q.state)) }
    if q.session != asker.session { return .failure(.askerSessionChanged) }
    if let e = q.expires, e < now { return .failure(.expired) }
    guard q.approvalRole != nil, let bound = q.approvalSession else { return .failure(.noLink) }
    switch target {
    case .failure(let e): return .failure(.target(e))
    case .success(let t):
        if t.session != bound { return .failure(.targetSessionChanged) }
        return .success(t)
    }
}
