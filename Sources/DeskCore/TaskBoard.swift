import Foundation

/// Reads the team card board (`herdr-task board --json`) only when the ledger folder changed.
public final class TaskBoardSource {
    private let stamp: () -> Date?
    private let run: () -> HcResult
    private let now: () -> Date
    private var lastStamp: Date?
    private var retryAt: Date?
    static let backoff: TimeInterval = 30

    public init(stamp: @escaping () -> Date?, run: @escaping () -> HcResult, now: @escaping () -> Date = Date.init) {
        self.stamp = stamp; self.run = run; self.now = now
    }

    /// The board dict when the ledger changed since the last read; nil when unchanged, missing or unreadable.
    /// A failed read is not repeated for the same ledger state until the backoff passes.
    public func poll() -> [String: Any]? {
        guard let current = stamp() else { return nil }
        if current == lastStamp, retryAt.map({ now() < $0 }) ?? true { return nil }
        lastStamp = current
        let result = run()
        guard result.code == 0, !result.timedOut, let data = result.out.data(using: .utf8),
              let board = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            retryAt = now().addingTimeInterval(Self.backoff)
            return nil
        }
        retryAt = nil
        return board
    }

    /// Newest modification time of the ledger folder and its team files (appends change the file, not the folder).
    public static func folderStamp(_ dir: URL) -> Date? {
        let fm = FileManager.default
        guard let own = (try? fm.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date else { return nil }
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .reduce(own) { max($0, $1) }
    }

    /// The ledger folder plus the computer list (`machines.json`) beside it: either changing re-reads the board.
    public static func boardStamp(_ state: URL) -> Date? {
        let machines = state.deletingLastPathComponent().appendingPathComponent("machines.json")
        let listed = (try? FileManager.default.attributesOfItem(atPath: machines.path))?[.modificationDate] as? Date
        switch (folderStamp(state), listed) {
        case let (a?, b?): return max(a, b)
        case let (a, b): return a ?? b
        }
    }
}

public enum TaskBoard {
    static let phase = ["working": "working", "review": "result-sent", "done": "acked", "cancelled": "acked"]

    /// Card states as handoff flow signals (worker = card owner, lead = that team's live lead).
    public static func flows(board: [String: Any], terms: [Term]) -> [HandoffFlow] {
        let live = terms.filter { $0.state == "live" }
        func unique(_ match: (Term) -> Bool) -> Term? {
            let found = live.filter(match)
            return found.count == 1 ? found[0] : nil
        }
        func party(_ t: Term) -> HandoffParty { HandoffParty(address: t.address, session: t.session, role: t.role ?? "") }
        var out: [HandoffFlow] = []
        let teams = board["teams"] as? [String: Any] ?? [:]
        for team in teams.keys.sorted() {
            let cards = (teams[team] as? [String: Any])?["cards"] as? [[String: Any]] ?? []
            // herdr-flow mirrors first, real cards last: the book takes the last match, so a card wins.
            let ordered = cards.filter { $0["kind"] as? String == "flow" } + cards.filter { $0["kind"] as? String != "flow" }
            for card in ordered {
                guard let id = card["id"] as? String, let state = card["state"] as? String, let phase = phase[state],
                      let owner = card["owner"] as? [String: Any], let key = owner["address"] as? String else { continue }
                let session = owner["session"] as? String
                let isFlow = card["kind"] as? String == "flow"
                let worker = isFlow ? unique { $0.role == key } : unique { $0.address == key && (session == nil || $0.session == session) }
                let leadRole = card["lead"] as? String
                let lead = isFlow && leadRole != nil
                    ? unique { $0.role == leadRole }
                    : unique { $0.labels["team.id"] == team && $0.labels["team.role"] == "lead" }
                guard let worker, let lead else { continue }
                out.append(HandoffFlow(worker: party(worker), lead: party(lead), id: id, phase: phase,
                                       updatedAt: ms(card["updated"] as? String)))
            }
        }
        return out
    }

    static func ms(_ iso: String?) -> Double? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        return (d.timeIntervalSince1970 * 1000).rounded()
    }
}
