import Foundation

/// A question a lead registered explicitly with `herdr-ask open` (ask.* labels on its own terminal).
public struct Question: Equatable {
    public var id: String
    public var text: String
    public var state: String
    public var session: String
    public var expires: Date?
    /// Optional explicit link (herdr-ask --approval-role): the role whose terminal awaits the person's approval,
    /// bound to that terminal's session when linked. Empty labels mean "no link".
    public var approvalRole: String?
    public var approvalSession: String?

    public init?(labels: [String: String]) {
        guard let id = labels["ask.id"], !id.isEmpty, let text = labels["ask.text"] else { return nil }
        self.id = id; self.text = text
        state = labels["ask.state"] ?? "open"
        session = labels["ask.session"] ?? ""
        expires = labels["ask.expires"].flatMap { ISO8601DateFormatter().date(from: $0) }
        approvalRole = labels["ask.approval_role"].flatMap { $0.isEmpty ? nil : $0 }
        approvalSession = labels["ask.approval_session"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

public enum Refusal: Error, Equatable, CustomStringConvertible {
    case emptyText, tooLong, badText
    case role(ResolveError)
    case noQuestion, otherQuestion, notOpen(String), sessionChanged, expired, busy(String)
    case alreadyHandled(String), lockHeld, ledgerError(String)

    public var description: String {
        switch self {
        case .emptyText: return "답장 내용이 비어 있어요."
        case .tooLong: return "답장은 2000자까지 보낼 수 있어요."
        case .badText: return "보낼 수 없는 문자가 있어요."
        case .role(.missing): return "이 담당의 실행 중인 대화를 찾지 못했어요."
        case .role(.ambiguous): return "같은 담당이 둘 이상 실행 중이라 보내지 않았어요."
        case .role(.notAgent): return "이 담당은 지금 AI가 아닌 셸이라 보내지 않았어요."
        case .noQuestion: return "이 담당에게 열린 질문이 없어요."
        case .otherQuestion: return "총괄이 다른 질문으로 바꿨어요. 새 질문을 확인해 주세요."
        case .notOpen(let s): return "이 질문은 이미 '\(s)' 상태예요."
        case .sessionChanged: return "총괄 세션이 바뀌어(재시작·복구) 이 질문은 만료됐어요."
        case .expired: return "질문 기한이 지났어요."
        case .busy(let s): return "총괄이 지금 '\(s)' 상태라 보내지 않았어요."
        case .alreadyHandled(let s): return "이 질문에는 이미 전송 기록(\(s))이 있어요."
        case .lockHeld: return "다른 답장을 보내는 중이에요. 잠시 후 다시 시도하세요."
        case .ledgerError(let s): return "전송 기록을 남기지 못해 보내지 않았어요: \(s)"
        }
    }
}

public let maxAnswerLength = 2000

public func checkText(_ text: String) -> Refusal? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return .emptyText }
    if t.count > maxAnswerLength { return .tooLong }
    if t.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && $0 != "\n" && $0 != "\t") }) { return .badText }
    return nil
}

/// Everything must still hold right before sending, re-read from hc (not from the page).
public func validate(term: Term, questionId: String, now: Date = Date()) -> Refusal? {
    guard term.isAgent else { return .role(.notAgent) }
    guard let q = Question(labels: term.labels) else { return .noQuestion }
    if q.id != questionId { return .otherQuestion }
    if q.state != "open" { return .notOpen(q.state) }
    if q.session != term.session { return .sessionChanged }
    if let e = q.expires, e < now { return .expired }
    if let s = term.status, ["blocked", "error"].contains(s) { return .busy(s) }
    return nil
}

public func outgoingMessage(questionId: String, text: String) -> String {
    "[User reply · Question \(questionId) · HerdrDesk]\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
}
