import Foundation

public let agentApps: Set<String> = ["codex", "claude-code"]

/// The part of a core terminal the app uses. Screen text is never read.
public struct Term: Equatable {
    public var address: String
    public var name: String?
    public var parent: String?
    public var state: String
    public var app: String?
    public var status: String?
    public var statusMessage: String?
    /// OSC 7501 `kind` of a blocked report: permission, question or auth (the program's own word, capped).
    public var statusKind: String?
    public var cols: Int?
    public var rows: Int?
    public var turn: Int
    public var createdMs: Int64
    public var pid: Int64
    public var labels: [String: String]
    /// When the core last changed this terminal's status (hc `status_ms`). Not "now"; nil when the source gave none.
    public var statusMs: Int64?
    /// When this app last received this terminal from a live snapshot or a successful `hc get`. Never a status change time.
    public var seenMs: Int64 = 0
    public var modelOptions: [String: String] = [:]

    public var isAgent: Bool { app.map { agentApps.contains($0) } ?? false }
    public var role: String? { labels["recovery.role"] }
    /// Changes when the terminal is recreated or its process restarts (reboot / recovery).
    public var session: String { "\(createdMs):\(pid)" }

    public init?(json: [String: Any]) {
        guard let address = json["address"] as? String else { return nil }
        self.address = address
        name = json["name"] as? String
        parent = json["parent"] as? String
        state = json["state"] as? String ?? "unknown"
        if let s = json["status"] as? [String: Any] {
            app = s["app"] as? String; status = s["state"] as? String
            statusMessage = (s["msg"] as? String).map { String($0.prefix(500)) }
            statusKind = (s["kind"] as? String).map { String($0.prefix(24)) }
        } else {
            app = json["agent"] as? String; status = json["status"] as? String
        }
        cols = json["cols"] as? Int
        rows = json["rows"] as? Int
        turn = (json["turn"] as? NSNumber)?.intValue ?? 0
        statusMs = (json["status_ms"] as? NSNumber)?.int64Value
        createdMs = (json["created_ms"] as? NSNumber)?.int64Value ?? 0
        pid = (json["pid"] as? NSNumber)?.int64Value ?? 0
        var l: [String: String] = [:]
        for (k, v) in json["labels"] as? [String: Any] ?? [:] { if let s = v as? String { l[k] = s } }
        labels = l
        let reported = json["status"] as? [String: Any] ?? [:]
        modelOptions["reportedModel"] = ModelOptions.clean(reported["model"])
        modelOptions["reportedEffort"] = ModelOptions.clean(reported["reasoning_effort"])
        let launch = ModelOptions.launch(json["argv"] as? [String] ?? [])
        modelOptions["launchModel"] = launch["model"]
        modelOptions["launchEffort"] = launch["effort"]
    }

    /// What the web page may see: no argv, cwd, screen or unrelated labels.
    public var publicJSON: [String: Any] {
        var options = modelOptions
        let defaults = address.contains("/") ? [:] : ModelOptions.localDefaults[app ?? ""] ?? [:]
        options["defaultModel"] = defaults["model"]
        options["defaultEffort"] = defaults["effort"]
        let keep = labels.filter { k, _ in
            k == "recovery.role" || k == "display.title" || k == "task.spawned" || k.hasPrefix("team.") || k.hasPrefix("dashboard.") || k.hasPrefix("ask.")
                || k.hasPrefix("flow.") || k.hasPrefix("flowack.") || k.hasPrefix("result.")
        }
        return ["address": address, "name": name ?? NSNull(), "parent": parent ?? NSNull(), "state": state, "agent": app ?? NSNull(), "status": status ?? "unknown",
                "turn": turn, "session": session, "statusMessage": statusMessage ?? "", "statusKind": statusKind ?? "", "labels": keep,
                "program": ["agent": isAgent], "statusMs": statusMs.map { NSNumber(value: $0) } ?? NSNull(),
                "seenMs": NSNumber(value: seenMs), "createdMs": NSNumber(value: createdMs), "modelOptions": options]
    }
}

public enum StoreChange: Equatable { case none, snapshot, refresh(String) }

/// Live terminal table fed by `hc events --json`: first line is a snapshot, then events. A `missed` message (the
/// subscriber fell behind) carries a fresh snapshot and replaces the table. Title events (~30/s) are dropped; any other
/// event on a terminal asks for one re-read of it (events lack `status_ms` and model details, which a read has).
public final class TerminalStore {
    public private(set) var terms: [String: Term] = [:]
    public init() {}

    @discardableResult
    public func apply(line: String, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> StoreChange {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .none }
        let resync = (obj["method"] as? String) == "missed" ? (obj["params"] as? [String: Any])?["terminals"] : nil
        if let list = (obj["terminals"] ?? resync) as? [[String: Any]] {
            var next: [String: Term] = [:]
            for j in list { if var t = Term(json: j), t.state == "live" { t.seenMs = nowMs; next[t.address] = t } }
            terms = next
            return .snapshot
        }
        guard let params = obj["params"] as? [String: Any], let address = params["terminal"] as? String else { return .none }
        if (params["type"] as? String) == "title" { return .none }
        return .refresh(address)
    }

    /// Result of `hc get <address>` (or nil when it is gone / finished).
    public func replace(address: String, with json: [String: Any]?, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        if let json, var t = Term(json: json), t.state == "live" { t.seenMs = nowMs; terms[address] = t } else { terms[address] = nil }
    }

    /// Applies an `hc get <address>` result. Only a definite answer changes the table: a live terminal
    /// replaces the entry, a finished one or `not_found` removes it. A timeout, an hc failure or
    /// unreadable output keeps the last known entry (a transient error must not hide a live terminal).
    public func apply(get r: HcResult, address: String, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        guard !r.timedOut else { return }
        func object(_ s: String) -> [String: Any]? {
            s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        if r.code == 0 {
            guard let j = object(r.out), Term(json: j) != nil else { return }
            replace(address: address, with: j, nowMs: nowMs)
            return
        }
        let error = (object(r.err) ?? object(r.out))?["error"] as? [String: Any]
        if (error?["kind"] as? String) == "not_found" { terms[address] = nil }
    }

    public var publicList: [[String: Any]] {
        let commands = CommandAuthority.currentTeams
        return terms.values.sorted { $0.address < $1.address }.map { t in
            var j = t.publicJSON
            if let c = CommandAuthority.metadata(for: t, teams: commands) { j["command"] = c }
            return j
        }
    }
}

/// Connection gate for the event stream. A stream generation changes whenever the stream ends; refresh
/// results gathered under an older generation (or while disconnected) are dropped, and the page is told
/// "live" only after a fresh snapshot of the current stream — never by a late refresh after a loss.
public struct StreamGate: Equatable {
    public private(set) var generation = 0
    public private(set) var live = false
    public private(set) var lostMs: Int64?
    public init() {}
    /// A new stream process started (not yet live until its snapshot arrives).
    public mutating func started() { generation += 1; live = false }
    public mutating func snapshot() { live = true; lostMs = nil }
    public mutating func lost(nowMs: Int64) { generation += 1; live = false; lostMs = nowMs }
    /// May refresh results gathered under `gen` be applied and announced?
    public func accepts(_ gen: Int) -> Bool { live && gen == generation }
    /// Is a callback (output / exit) from the stream process launched under `gen` still the current one?
    public func isCurrent(_ gen: Int) -> Bool { gen == generation }
    public var conn: String { live ? "live" : (lostMs == nil ? "connecting" : "lost") }
}

public enum ResolveError: Error, Equatable { case missing, ambiguous, notAgent }

/// A role resolves to exactly one live AI terminal (like domain.js resolve); shells never qualify.
public func resolve(role: String, in terms: [Term]) -> Result<Term, ResolveError> {
    let all = terms.filter { $0.state == "live" && $0.role == role }
    let agents = all.filter { $0.isAgent }
    if agents.count > 1 { return .failure(.ambiguous) }
    if let a = agents.first { return .success(a) }
    return .failure(all.isEmpty ? .missing : .notAgent)
}
