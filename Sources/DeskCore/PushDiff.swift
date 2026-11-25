import Foundation

/// Leaves out of a page update the large parts that did not change since the last update the page received.
/// The page keeps its previous value for any of these keys that is missing. A fresh page (reset) gets everything.
public struct PushDiff {
    public static let largeKeys: Set<String> = ["replies", "teamMessages", "liveMessages", "liveTurns", "lineage",
                                                "configuredTeams", "spaces", "systemSounds", "archiveRoles", "machines", "ledger"]
    private var sent: [String: Data] = [:]
    public init() {}

    public mutating func reset() { sent.removeAll() }

    public mutating func trim(_ payload: [String: Any]) -> [String: Any] {
        var out = payload
        for key in Self.largeKeys {
            guard let value = payload[key] else { continue }
            // sortedKeys: the same content always serialises the same way
            guard let data = try? JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys]) else { continue }
            if sent[key] == data { out.removeValue(forKey: key) } else { sent[key] = data }
        }
        return out
    }
}
