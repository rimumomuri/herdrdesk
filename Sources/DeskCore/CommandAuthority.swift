import Foundation
import CoreFoundation

/// Read-only projection of the HQ command register. No new watcher, state write or routing.
public enum CommandAuthority {
    public static func metadata(for term: Term, teams: [String: Any]) -> [String: Any]? {
        guard term.state == "live", term.isAgent,
              let team = term.labels["team.id"], let r = teams[team] as? [String: Any],
              let owner = r["owner"] as? String, owner == term.role,
              (r["ownerSession"] as? String) == term.session,
              let epochValue = r["epoch"] as? NSNumber,
              CFGetTypeID(epochValue) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: epochValue.objCType)),
              epochValue.int64Value > 0, epochValue.int64Value <= 9_007_199_254_740_991,
              let mode = r["mode"] as? String, ["acting", "handback"].contains(mode),
              let pausedValue = r["paused"] as? NSNumber,
              CFGetTypeID(pausedValue) == CFBooleanGetTypeID() else { return nil }
        return ["team": team, "epoch": epochValue.intValue, "mode": mode, "paused": pausedValue.boolValue]
    }
    public static func teams(at url: URL?) -> [String: Any] {
        guard let url, let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              attrs.isRegularFile == true, attrs.isSymbolicLink != true,
              let d = try? Data(contentsOf: url), d.count <= 256 * 1024,
              let root = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return root["teams"] as? [String: Any] ?? [:]
    }
    static var currentTeams: [String: Any] {
        let e = ProcessInfo.processInfo.environment
        if let path = e["HERDRDESK_COMMANDS"] { return teams(at: URL(fileURLWithPath: path)) }
        return [:]
    }
}
