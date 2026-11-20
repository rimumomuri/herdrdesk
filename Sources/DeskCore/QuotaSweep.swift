import Foundation

/// A quota edge schedules one bounded, metadata-only sweep. Reading another known error never
/// propagates a shared-account assumption or recursively starts another sweep.
public struct QuotaSweep {
    private var incidents = Set<String>()
    public init() {}
    public static func limited(_ t: Term) -> Bool {
        guard t.state == "live", t.app == "claude-code", t.status == "error" else { return false }
        return (t.statusMessage ?? "").range(of: "hit.{0,20}(limit|quota)|usage limit|rate.?limit|quota exceeded|limit reached|한도|用量上限", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func key(_ t: Term) -> String {
        "\(t.address)|\(t.session)|\(t.statusMs ?? 0)|\(t.statusMessage ?? "")"
    }
    public mutating func plan(_ terms: [Term]) -> [Term] {
        let limited = terms.filter(Self.limited), next = Set(limited.map(Self.key))
        let fresh = next.subtracting(incidents); incidents = next
        guard !fresh.isEmpty else { return [] }
        return terms.filter { $0.state == "live" && $0.app == "claude-code" && !Self.limited($0) }
            .sorted { $0.address < $1.address }
    }
    public mutating func settle(_ terms: [Term]) {
        incidents = Set(terms.filter(Self.limited).map(Self.key))
    }
    public mutating func interrupted() { incidents.removeAll() }
    public static func accepts(original: Term, current: Term?, fetched: Term?) -> Bool {
        guard let current, let fetched else { return false }
        return current == original && fetched.address == original.address && fetched.session == original.session
            && fetched.app == "claude-code" && fetched.state == "live"
    }
}
