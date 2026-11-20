import Foundation

public enum SendOutcome: Equatable {
    case sent(turn: Int?)
    /// hc said it did not start (e.g. started:false). Safe to try again later.
    case notSent(String)
    /// Timed out or unreadable answer: it may or may not have arrived. Never retried automatically.
    case needsCheck(String)
    case refused(Refusal)
}

public final class AnswerSender {
    let hc: HcRunning
    public let ledger: Ledger
    let lockPath: String
    let now: () -> Date
    let sendTimeout: TimeInterval
    let originReceipts: UserDispatchReceipts?
    let lineage: LineageStore?
    func stamp() -> String { iso() }

    public init(hc: HcRunning, ledger: Ledger, lockPath: String, sendTimeout: TimeInterval = 90, now: @escaping () -> Date = Date.init,
                originReceipts: UserDispatchReceipts? = nil, lineage: LineageStore? = nil) {
        self.hc = hc; self.ledger = ledger; self.lockPath = lockPath; self.now = now; self.sendTimeout = sendTimeout
        self.originReceipts = originReceipts
        self.lineage = lineage
    }

    public static func defaultLockPath() -> String {
        DeskPaths.data.appendingPathComponent("send.lock").path
    }

    private func iso() -> String { ISO8601DateFormatter().string(from: now()) }

    /// Fresh view of one role, straight from hc (the page's copy is never trusted).
    public func fetchRole(_ role: String) -> Result<Term, Refusal> {
        let ls = hc.run(["ls", "--json", "--label", "recovery.role=\(role)"], timeout: 15)
        guard !ls.timedOut, ls.code == 0, let d = ls.out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let list = obj["terminals"] as? [[String: Any]] else { return .failure(.role(.missing)) }
        var terms: [Term] = []
        for item in list {
            guard let addr = item["address"] as? String else { continue }
            let g = hc.run(["get", addr], timeout: 15)
            if g.code == 0, let gd = g.out.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: gd) as? [String: Any], let t = Term(json: j) { terms.append(t) }
        }
        switch resolve(role: role, in: terms) {
        case .success(let t): return .success(t)
        case .failure(let e): return .failure(.role(e))
        }
    }

    /// Fresh re-read of a linked question and its approval target, straight from hc.
    public func fetchApproval(questionId: String, askerRole: String) -> Result<Term, ApprovalRefusal> {
        // Asker uniqueness by the question id itself (labels only, never body text): two live AIs → refused.
        guard let carriers = freshTerms(label: "ask.id=\(questionId)") else { return .failure(.noQuestion) }
        let asker: Term
        switch askerOf(questionId: questionId, in: carriers) {
        case .failure(let e): return .failure(e)
        case .success(let t): asker = t
        }
        guard asker.role == askerRole else { return .failure(.noQuestion) }
        guard let q = Question(labels: asker.labels), q.id == questionId else { return .failure(.noQuestion) }
        guard let role = q.approvalRole else { return .failure(.noLink) }
        let target: Result<Term, ResolveError>
        switch fetchRole(role) {
        case .success(let t): target = .success(t)
        case .failure(.role(let e)): target = .failure(e)
        case .failure: target = .failure(.missing)
        }
        // Decide with the clock read AFTER the fresh reads finished (a question may expire meanwhile).
        return checkApproval(questionId: questionId, asker: asker, target: target, now: now())
    }

    /// Fresh `hc ls --label k=v` + `hc get` of each hit. nil when the listing itself failed.
    private func freshTerms(label: String) -> [Term]? {
        let ls = hc.run(["ls", "--json", "--label", label], timeout: 15)
        guard !ls.timedOut, ls.code == 0, let d = ls.out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let list = obj["terminals"] as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let addr = item["address"] as? String else { return nil }
            let g = hc.run(["get", addr], timeout: 15)
            guard g.code == 0, !g.timedOut, let gd = g.out.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: gd) as? [String: Any] else { return nil }
            return Term(json: j)
        }
    }

    /// started:true → sent; started:false → surely not sent; anything else (timeout, unreadable) → unknown.
    static func interpret(_ r: HcResult) -> SendOutcome {
        let obj = r.out.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if r.timedOut { return .needsCheck("응답을 기다리다 시간이 초과됐어요. 전달됐는지 알 수 없어요.") }
        if let started = obj?["started"] as? Bool {
            return started ? .sent(turn: (obj?["turn"] as? NSNumber)?.intValue)
                : .notSent((obj?["reason"] as? String) ?? (obj?["status"] as? String) ?? "시작되지 않음")
        }
        return .needsCheck(r.err.isEmpty ? "hc 응답을 해석하지 못했어요." : String(r.err.prefix(200)))
    }

    public func send(role: String, questionId: String, text: String) -> SendOutcome {
        if let r = checkText(text) { return .refused(r) }
        guard let lock = FileLock.tryAcquire(path: lockPath) else { return .refused(.lockHeld) }
        defer { lock.release() }
        if !ledger.allowsSend(questionId) { return .refused(.alreadyHandled(ledger.read(questionId)?.state ?? "?")) }
        let term: Term
        switch fetchRole(role) {
        case .failure(let r): return .refused(r)
        case .success(let t): term = t
        }
        if let r = validate(term: term, questionId: questionId, now: now()) { return .refused(r) }
        var entry = LedgerEntry(state: "sending", role: role, address: term.address, session: term.session, at: iso(), turn: nil, note: nil)
        do { try ledger.write(questionId, entry) } catch { return .refused(.ledgerError("\(error.localizedDescription)")) }
        _ = hc.run(["label", term.address, "ask.state=sending"], timeout: 15)   // informational only

        var payload = outgoingMessage(questionId: questionId, text: text)
        if let lineage, let question = Question(labels:term.labels) {
            var bound = LineageIdentity(term)
            var verified = true
            if let role = question.approvalRole {
                if case .success(let target) = fetchRole(role), target.session == question.approvalSession { bound = LineageIdentity(target) }
                else { verified = false }
            }
            if verified, let header = try? lineage.continuationHeader(requestId:questionId,requester:LineageIdentity(term),target:bound,now:now()) { payload = header + payload }
        }
        var intent: UserDispatchIntent?
        do {
            intent = try originReceipts?.arm(sourceID:questionId,address:term.address,session:term.session,payload:payload,now:now())
            if let intent { payload = intent.payload }
        } catch {
            entry.state = "not_sent"; entry.note = "user request receipt unavailable"
            try? ledger.write(questionId,entry)
            _ = hc.run(["label",term.address,"ask.state=open"],timeout:15)
            return .refused(.ledgerError("사용자 요청 확인 기록을 준비하지 못했어요."))
        }
        let r = hc.run(["send", "--json", term.address, payload], timeout: sendTimeout)
        let outcome = AnswerSender.interpret(r)
        if let intent { try? originReceipts?.recordSenderResult(intent.id,outcome:outcome) }
        switch outcome {
        case .sent(let turn):
            entry.state = "sent"; entry.turn = turn
            _ = hc.run(["label", term.address, "ask.state=sent", "ask.answered=\(iso())", "ask.sent_turn=\(turn.map(String.init) ?? "")"], timeout: 15)
        case .notSent(let why):
            entry.state = "not_sent"; entry.note = why
            _ = hc.run(["label", term.address, "ask.state=open"], timeout: 15)
        case .needsCheck(let why):
            entry.state = "needs_check"; entry.note = why
            _ = hc.run(["label", term.address, "ask.state=needs-check"], timeout: 15)
        case .refused: break
        }
        entry.at = iso()
        try? ledger.write(questionId, entry)
        return outcome
    }

    /// The person checked Herdr and says what happened to a `needs_check` send.
    public func resolveUnknown(questionId: String, delivered: Bool) -> Refusal? {
        guard let lock = FileLock.tryAcquire(path: lockPath) else { return .lockHeld }
        defer { lock.release() }
        guard var e = ledger.read(questionId), e.state == "needs_check" else { return .notOpen(ledger.read(questionId)?.state ?? "기록 없음") }
        e.state = delivered ? "resolved_sent" : "resolved_not_sent"; e.at = iso()
        do { try ledger.write(questionId, e) } catch { return .ledgerError(error.localizedDescription) }
        _ = hc.run(["label", e.address, delivered ? "ask.state=sent" : "ask.state=open"], timeout: 15)
        return nil
    }
}
