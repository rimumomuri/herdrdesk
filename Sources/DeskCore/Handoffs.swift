import Foundation

/// One side of a handoff: a terminal session (or the HerdrDesk user, `desk`).
public struct HandoffParty: Codable, Hashable {
    public var address, session, role: String
    public init(address: String, session: String, role: String) { self.address = address; self.session = session; self.role = role }
    public static let desk = HandoffParty(address: "desk", session: "desk", role: "you")
    /// Same terminal session. An unknown session (remote or unlabelled target) matches by address.
    func same(_ other: HandoffParty) -> Bool {
        address == other.address && (session == other.session || session.isEmpty || other.session.isEmpty)
    }
    var json: [String: Any] { ["address": address, "session": session, "role": role] }
}

/// A message one party sent another. `source`: receiver (hc envelope), sender (hc send call) or desk.
public struct HandoffMessage {
    public var from, to: HandoffParty
    public var at: Double
    public var body: String
    public var source: String
    public init(from: HandoffParty, to: HandoffParty, at: Double, body: String, source: String) {
        self.from = from; self.to = to; self.at = at; self.body = body; self.source = source
    }
}

/// herdr-flow labels: phase working | result-sent | acked | done.
public struct HandoffFlow {
    public var worker, lead: HandoffParty
    public var id, phase: String
    /// `flow.updated` in ms. Labels outlive their task, so a flow older than the edge is ignored.
    public var updatedAt: Double?
    public init(worker: HandoffParty, lead: HandoffParty, id: String, phase: String, updatedAt: Double?) {
        self.worker = worker; self.lead = lead; self.id = id; self.phase = phase; self.updatedAt = updatedAt
    }
}

/// A lineage edge between two agents.
public struct HandoffLineage {
    public var from, to: HandoffParty
    public var id: String
    public var completed: Bool
    /// Latest of acceptedAt / completedAt in ms; lineage edges older than the handoff are ignored.
    public var at: Double?
    public init(from: HandoffParty, to: HandoffParty, id: String, completed: Bool, at: Double?) {
        self.from = from; self.to = to; self.id = id; self.completed = completed; self.at = at
    }
}

public struct HandoffSignals {
    public var status: [String: String]      // address → hc status
    public var session: [String: String]     // address → current session
    public var flows: [HandoffFlow]
    public var lineage: [HandoffLineage]
    /// address → when its status last changed (hc `status_ms`). A "working" that began long before a message
    /// arrived and never changed since is a stuck label, not work on that message.
    public var statusSince: [String: Double]
    public init(status: [String: String], session: [String: String], flows: [HandoffFlow], lineage: [HandoffLineage],
                statusSince: [String: Double] = [:]) {
        self.status = status; self.session = session; self.flows = flows; self.lineage = lineage; self.statusSince = statusSince
    }
}

public struct HandoffEdge: Codable {
    public var id: String
    public var from, to: HandoffParty
    public var openedAt, updatedAt: Double
    public var closedAt: Double?
    /// open | weak | unconfirmed | closed | stale
    public var state: String
    /// transcript | lineage | flow
    public var signal: String
    public var summary: String
    public var workedSinceOpen: Bool
    public var pendingReplyAt: Double?
    public var pendingCardId: String?
    public var busyAfterReply: Bool?
    public var returnedAt: Double?
    public var flowId: String?
    public var lineageId: String?
    /// When the receiver answered it (a reply card). Kept on the edge: cards are capped and pruned.
    public var answeredAt: Double? = nil
    var isOpen: Bool { ["open", "weak", "unconfirmed"].contains(state) }
}

public struct HandoffCard: Codable {
    public var id: String
    public var at: Double
    /// assign | reply | progress | message | pending
    public var kind: String
    public var from, to: HandoffParty
    public var body: String
}

/// Who handed what to whom, from observed messages and terminal status. Pure: no I/O, no clock.
public final class HandoffBook {
    public static let mergeWindow = 120_000.0, replyWindow = 30_000.0, weakAfter = 600_000.0,
        deskIdleAfter = 600_000.0, staleAfter = 21_600_000.0, keepFor = 604_800_000.0,
        maxCards = 1000, returnFlash = 3_000.0, snapshotCards = 300, cardBodyLimit = 300,
        answerWindow = 7_200_000.0

    public private(set) var edges: [HandoffEdge]
    public private(set) var cards: [HandoffCard]

    public init(edges: [HandoffEdge] = [], cards: [HandoffCard] = []) { self.edges = edges; self.cards = cards }

    public func record(_ m: HandoffMessage) {
        let body = Self.summary(m.body)
        guard !body.isEmpty, !m.from.same(m.to) else { return }
        // The same message seen from both sides (sender's hc send and receiver's envelope) counts once.
        if cards.contains(where: { $0.from.same(m.from) && $0.to.same(m.to) && abs($0.at - m.at) <= Self.mergeWindow
            && $0.body.prefix(200) == body.prefix(200) }) { return }
        if let i = edges.lastIndex(where: { $0.isOpen && $0.from.same(m.to) && $0.to.same(m.from) }) {
            if edges[i].pendingCardId != nil { resolvePending(&edges[i], as: "message") }
            let card = addCard(edges[i], at: m.at, kind: "pending", from: m.from, to: m.to, body: body)
            edges[i].pendingReplyAt = m.at
            edges[i].pendingCardId = card
            edges[i].busyAfterReply = false
            return
        }
        if let i = edges.lastIndex(where: { $0.isOpen && $0.from.same(m.from) && $0.to.same(m.to) }) {
            // Anything more sent on a handoff that is still open adds to it; only a new handoff is "assign".
            edges[i].updatedAt = max(edges[i].updatedAt, m.at)
            edges[i].summary = body
            _ = addCard(edges[i], at: m.at, kind: "message", from: m.from, to: m.to, body: body)
            return
        }
        // A word sent right after the other side finished (e.g. "got it, checking") belongs to that handoff.
        if m.from != .desk, let i = edges.lastIndex(where: { !$0.isOpen && $0.from.same(m.from) && $0.to.same(m.to) }),
           let ended = edges[i].closedAt, m.at >= ended - Self.mergeWindow, m.at - ended <= Self.mergeWindow {
            _ = addCard(edges[i], at: m.at, kind: "message", from: m.from, to: m.to, body: body)
            return
        }
        // The first answer to something the other side handed over (and that really finished) joins it:
        // it is not new work, so a busy receiver must not keep it "waiting" for hours.
        if m.from != .desk, m.to != .desk,
           let i = edges.lastIndex(where: { ($0.from.same(m.to) && $0.to.same(m.from)) || ($0.from.same(m.from) && $0.to.same(m.to)) }),
           edges[i].from.same(m.to), edges[i].state == "closed", let ended = edges[i].closedAt, m.at - ended <= Self.answerWindow,
           edges[i].answeredAt == nil {
            edges[i].answeredAt = m.at
            _ = addCard(edges[i], at: m.at, kind: "reply", from: m.from, to: m.to, body: body)
            return
        }
        let edge = HandoffEdge(id: "h:\(m.from.address):\(m.to.address):\(Int(m.at))", from: m.from, to: m.to,
                               openedAt: m.at, updatedAt: m.at, closedAt: nil, state: "open", signal: "transcript",
                               summary: body, workedSinceOpen: false, pendingReplyAt: nil, pendingCardId: nil,
                               busyAfterReply: nil, returnedAt: nil, flowId: nil, lineageId: nil)
        edges.append(edge)
        _ = addCard(edge, at: m.at, kind: "assign", from: m.from, to: m.to, body: body)
    }

    public func observe(_ s: HandoffSignals, now: Double) {
        for i in edges.indices where edges[i].isOpen {
            var e = edges[i]
            defer { edges[i] = e }
            let stuck = s.status[e.to.address] == "working"
                && (s.statusSince[e.to.address].map { $0 < e.openedAt - Self.staleAfter } ?? false)
            let working = s.status[e.to.address] == "working" && !stuck
            if working {
                e.workedSinceOpen = true
                if e.state != "open" { e.state = "open" }
            }
            // herdr-flow is the strongest signal, but only a flow written for this handoff (not an old label).
            let fresh: (Double?) -> Bool = { at in at.map { $0 >= e.openedAt - Self.mergeWindow } ?? false }
            if let flow = s.flows.last(where: { $0.worker.same(e.to) && $0.lead.same(e.from) && fresh($0.updatedAt) }) {
                e.signal = "flow"; e.flowId = flow.id
                switch flow.phase {
                case "working":
                    e.state = "open"
                    if e.pendingReplyAt != nil { resolvePending(&e, as: "progress") }
                case "result-sent": close(&e, at: now, returned: now)
                default: close(&e, at: now, returned: e.returnedAt)
                }
                continue
            }
            if let link = s.lineage.last(where: { $0.from.same(e.from) && $0.to.same(e.to) && fresh($0.at) }) {
                e.signal = "lineage"; e.lineageId = link.id
                if link.completed { close(&e, at: now, returned: now); continue }
            }
            if now - e.updatedAt > Self.staleAfter { e.state = "stale"; e.closedAt = now; continue }
            // A restarted session or a terminal that is no longer live ends the handoff. An empty list means
            // the core is unreachable, not that every terminal is gone.
            for party in [e.from, e.to] where party != .desk && !party.session.isEmpty && !s.session.isEmpty {
                if s.session[party.address] != party.session { e.state = "closed"; e.closedAt = now }
            }
            if !e.isOpen { continue }
            if let pending = e.pendingReplyAt, now > pending {
                // The replier usually keeps working briefly after `hc send` (its final message). Seeing it
                // stop within the window makes the message the reply; still working when it ends: an update.
                if !working { resolvePending(&e, as: "reply"); close(&e, at: now, returned: pending); continue }
                if now - pending > Self.replyWindow { resolvePending(&e, as: "progress") }
            }
            if e.from == .desk {
                let delegating = edges.contains { $0.isOpen && $0.from.same(e.to) }
                if e.workedSinceOpen && !working && !delegating { close(&e, at: now, returned: now) }
                else if !e.workedSinceOpen && now - e.openedAt > Self.deskIdleAfter { close(&e, at: now, returned: nil) }
            } else {
                // The receiver took it and finished without handing it on: nothing is left to wait for. A receiver
                // whose status is stuck cannot show that, so its message counts as delivered after the weak window.
                let delegating = edges.contains { $0.isOpen && $0.from.same(e.to) }
                if e.workedSinceOpen && !working && !delegating && !stuck { close(&e, at: now, returned: now) }
                else if stuck && !delegating && now - e.updatedAt > Self.weakAfter { close(&e, at: now, returned: nil) }
                else if !e.workedSinceOpen && e.state == "open" && now - e.openedAt > Self.weakAfter { e.state = "weak" }
            }
        }
    }

    /// The target answered the HerdrDesk user directly.
    public func deskReply(from target: HandoffParty, at: Double, body: String) {
        guard let i = edges.lastIndex(where: { $0.isOpen && $0.from == .desk && $0.to.same(target) }) else { return }
        close(&edges[i], at: at, returned: at)
        _ = addCard(edges[i], at: at, kind: "reply", from: target, to: .desk, body: Self.summary(body))
    }

    /// A `herdr-reply` post (known by role and session, not address) answered the HerdrDesk user. It closes the open
    /// desk handoff to that session only when it came after the user's latest message there.
    public func publishedReply(role: String, session: String, at: Double) {
        guard !role.isEmpty, !session.isEmpty,
              let i = edges.lastIndex(where: { $0.isOpen && $0.from == .desk && $0.to.role == role && $0.to.session == session }),
              at >= edges[i].updatedAt else { return }
        close(&edges[i], at: at, returned: at)   // no card: the post is already shown from its own record
    }

    /// Never throws or refuses: closed history older than `keepFor` goes, then the oldest cards over the cap.
    public func prune(now: Double) {
        edges.removeAll { !$0.isOpen && ($0.closedAt ?? $0.updatedAt) < now - Self.keepFor }
        cards.removeAll { $0.at < now - Self.keepFor }
        if cards.count > Self.maxCards { cards.removeFirst(cards.count - Self.maxCards) }
    }

    /// After a restart nothing open can be confirmed from the transcript (readers start at EOF).
    public func markReloaded() {
        for i in edges.indices where edges[i].state == "open" { edges[i].state = "unconfirmed" }
    }

    public func webSnapshot(now: Double) -> [String: Any] {
        var shown: [[String: Any]] = []
        for e in edges {
            var state = e.state
            if !e.isOpen {
                guard let back = e.returnedAt, now - back <= Self.returnFlash, now >= back else { continue }
                state = "returning"
            }
            shown.append(["id": e.id, "from": e.from.json, "to": e.to.json, "state": state, "openedAt": e.openedAt,
                          "updatedAt": e.updatedAt, "summary": e.summary, "signal": e.signal])
        }
        let recent = cards.suffix(Self.snapshotCards).map { c -> [String: Any] in
            ["id": c.id, "at": c.at, "kind": c.kind, "from": c.from.json, "to": c.to.json, "body": String(c.body.prefix(Self.cardBodyLimit))]
        }
        return ["edges": shown, "cards": recent]
    }

    /// Cheap change detector for what the page shows (no bodies, no serialisation).
    public func signature(now: Double) -> String {
        var parts: [String] = []
        for e in edges {
            if e.isOpen { parts.append(e.id + ":" + e.state + ":" + String(Int(e.updatedAt)) + (e.pendingReplyAt == nil ? "" : ":p")) }
            else if let back = e.returnedAt, now >= back, now - back <= Self.returnFlash { parts.append(e.id + ":returning") }
        }
        parts.append(String(cards.count))
        parts.append(contentsOf: cards.suffix(20).map { $0.id + ":" + $0.kind })
        return parts.joined(separator: "|")
    }

    /// Whether time alone can change what is shown soon (reply windows, return flash, fresh arrows).
    public func needsFastTicks(now: Double) -> Bool {
        edges.contains { e in
            e.pendingReplyAt != nil || (e.isOpen && now - e.openedAt <= Self.returnFlash)
                || (e.returnedAt.map { now >= $0 && now - $0 <= Self.returnFlash } ?? false)
        }
    }
    public var hasOpenEdges: Bool { edges.contains { $0.isOpen } }

    private func close(_ e: inout HandoffEdge, at: Double, returned: Double?) {
        e.state = "closed"; e.closedAt = at; e.returnedAt = returned
        e.pendingReplyAt = nil; e.busyAfterReply = nil
    }

    private func resolvePending(_ e: inout HandoffEdge, as kind: String) {
        if let id = e.pendingCardId, let c = cards.lastIndex(where: { $0.id == id }) { cards[c].kind = kind }
        if kind == "reply" { e.answeredAt = e.pendingReplyAt ?? e.answeredAt }
        e.pendingReplyAt = nil; e.pendingCardId = nil; e.busyAfterReply = nil
    }

    private func addCard(_ edge: HandoffEdge, at: Double, kind: String, from: HandoffParty, to: HandoffParty, body: String) -> String {
        let id = "c:\(edge.id):\(Int(at)):\(cards.count)"
        cards.append(HandoffCard(id: id, at: at, kind: kind, from: from, to: to, body: body))
        return id
    }

    static func summary(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[HerdrDesk lineage "), let end = t.firstIndex(of: "\n") { t = String(t[t.index(after: end)...]) }
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
    }
}

/// Maps an `hc send` target (address, name, role or display title) to one live terminal, or nil when ambiguous.
public enum HandoffTarget {
    public static func resolve(_ target: String, in terms: [Term]) -> Term? {
        if let exact = terms.first(where: { $0.address == target }) { return exact }
        let matches = terms.filter { $0.name == target || $0.role == target || $0.labels["display.title"] == target }
        return matches.count == 1 ? matches.first : nil
    }
}
