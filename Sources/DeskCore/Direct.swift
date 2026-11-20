import Foundation

/// Free-form message from the composer to one member's existing session. The person's click on
/// 보내기 is the approval; nothing here sends on its own. Same safety as answers: shared lock,
/// a ledger keyed by message id (written before hc send), fresh re-validation, one hc send.
public final class DirectSender {
    let base: AnswerSender
    public let ledger: Ledger
    public init(base: AnswerSender, ledger: Ledger) { self.base = base; self.ledger = ledger }

    public static func defaultDir() -> URL { DeskPaths.data.appendingPathComponent("direct", isDirectory: true) }

    public static func message(_ text: String, images: [(path: String, a: Attachment)] = []) -> String {
        var out = "[User message · HerdrDesk]"
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { out += "\n\(t)" }
        if !images.isEmpty {
            // Honest wording (research hq-desk-image-attach): a file PATH, not an inline multimodal attachment.
            out += "\n\n[사용자 첨부 이미지 · 파일 경로 전달(직접 첨부 아님)]"
            for i in images {
                let fmt = i.path.lowercased().hasSuffix(".jpg") ? "JPEG" : "PNG"
                out += "\n- \(i.path) (\(fmt), \(i.a.width)×\(i.a.height), \(max(1, i.a.bytes / 1024))KB)"
            }
            out += "\n이미지를 직접 열어 확인해 주세요(Claude Code: Read 도구, Codex: view_image). 열 수 없으면 '이미지 열람 실패'라고 알려 주세요."
        }
        return out
    }

    public func send(role: String, session: String, messageId: String, text: String, attachments: [Attachment] = []) -> SendOutcome {
        send(role: role, session: session, messageId: messageId, text: text, attachments: attachments) {
            self.base.fetchRole(role)
        }
    }

    public func send(to target: Term, messageId: String, text: String, attachments: [Attachment] = [], conversationId: String? = nil) -> SendOutcome {
        send(role: target.role ?? target.address, session: target.session, messageId: messageId, text: text, attachments: attachments, conversationId:conversationId) {
            let response = self.base.hc.run(["get", "--json", target.address], timeout: 10)
            guard !response.timedOut, response.code == 0, let data = response.out.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let current = Term(json: json), current.address == target.address, current.role == target.role,
                  current.state == "live", current.isAgent, current.pid > 0 else { return .failure(.role(.missing)) }
            return .success(current)
        }
    }

    private func send(role: String, session: String, messageId: String, text: String, attachments: [Attachment], conversationId: String? = nil,
                      resolve: () -> Result<Term, Refusal>) -> SendOutcome {
        if attachments.isEmpty, let r = checkText(text) { return .refused(r) }
        if !attachments.isEmpty, text.count > maxAnswerLength || text.unicodeScalars.contains(where: { $0.value == 0 }) { return .refused(.badText) }
        if attachments.count > AttachmentStore.maxCount { return .refused(.badText) }
        guard messageId.range(of: "^m[A-Za-z0-9_-]{6,60}$", options: .regularExpression) != nil else { return .refused(.ledgerError("bad message id")) }
        guard let lock = FileLock.tryAcquire(path: base.lockPath) else { return .refused(.lockHeld) }
        defer { lock.release() }
        if ledger.read(messageId) != nil { return .refused(.alreadyHandled(ledger.read(messageId)?.state ?? "?")) }
        let term: Term
        switch resolve() {
        case .failure(let r): return .refused(r)
        case .success(let t): term = t
        }
        if term.session != session { return .refused(.sessionChanged) }        // the card the person looked at is not this session
        if let s = term.status, ["blocked", "error"].contains(s) { return .refused(.busy(s)) }
        var entry = LedgerEntry(state: "sending", role: role, address: term.address, session: term.session, at: base.stamp(), turn: nil,
                                note: attachments.isEmpty ? nil : "images: " + attachments.map { $0.file }.joined(separator: ", "))
        do { try ledger.write(messageId, entry) } catch { return .refused(.ledgerError(error.localizedDescription)) }
        // Images first: each file is placed beside the target session with hc put. Any failure → nothing is sent.
        var landed: [(path: String, a: Attachment)] = []
        for a in attachments {
            let r = base.hc.run(["put", "--json", term.address, a.file], timeout: 60)
            let obj = r.out.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard !r.timedOut, r.code == 0, let path = obj?["path"] as? String, path.hasPrefix("/") else {
                entry.state = "not_sent"; entry.note = "image put failed: \(a.name)"; entry.at = base.stamp()
                try? ledger.write(messageId, entry)
                return .notSent("이미지 '\(a.name)'을 전달하지 못해 메시지를 보내지 않았어요")
            }
            landed.append((path, a))
        }
        if !landed.isEmpty {
            entry.note = "images: " + landed.map { $0.path }.joined(separator: ", ")
            guard case .success(let current) = resolve(),
                  current.address == term.address, current.session == term.session,
                  !["blocked", "error"].contains(current.status ?? "") else {
                entry.state = "not_sent"
                entry.at = base.stamp()
                try? ledger.write(messageId, entry)
                return .notSent("The target session changed before delivery.")
            }
            try? ledger.write(messageId, entry)
        }
        var payload = DirectSender.message(text, images:landed)
        var intent: UserDispatchIntent?
        do {
            if let lineage = base.lineage {
                guard let conversationId else { throw LineageError.invalid }
                try lineage.createRoot(id:messageId,conversationId:conversationId,recipient:LineageIdentity(term),now:base.now())
                payload = try LineageStore.originHeader(id:messageId,conversationId:conversationId) + payload
            }
            intent = try base.originReceipts?.arm(sourceID:messageId,address:term.address,session:term.session,payload:payload,now:base.now())
            if let intent { payload = intent.payload }
        } catch {
            try? base.lineage?.rootDelivery(id:messageId,dispatchId:nil,outcome:.notSent("receipt unavailable"))
            entry.state = "not_sent"; entry.note = "user request receipt unavailable"
            try? ledger.write(messageId,entry)
            return .refused(.ledgerError("사용자 요청 확인 기록을 준비하지 못했어요."))
        }
        let r = base.hc.run(["send", "--json", term.address, payload], timeout: base.sendTimeout)
        let outcome = AnswerSender.interpret(r)
        if let intent { try? base.originReceipts?.recordSenderResult(intent.id,outcome:outcome) }
        try? base.lineage?.rootDelivery(id:messageId,dispatchId:intent?.id,outcome:outcome)
        switch outcome {
        case .sent(let t): entry.state = "sent"; entry.turn = t
        case .notSent(let w): entry.state = "not_sent"; entry.note = w
        case .needsCheck(let w): entry.state = "needs_check"; entry.note = w
        case .refused: break
        }
        entry.at = base.stamp()
        try? ledger.write(messageId, entry)
        return outcome
    }
}
