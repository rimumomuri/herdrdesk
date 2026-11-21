import Foundation

/// The computer settings sheet: turns a web request into a checked `herdr-task machine ...` argv.
/// The page never names a local folder: a suggestion is looked up by team from Mac Studio's own repo list.
public enum MachineSettings {
    static func safeName(_ value: Any?) -> String? {
        guard let s = value as? String, s.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }

    static func clean(_ value: Any?, max: Int) -> String? {
        guard let s = value as? String, !s.isEmpty, s.utf8.count <= max, !s.hasPrefix("-"),
              !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespaces.contains($0) })
        else { return nil }
        return s
    }

    public static func argv(_ body: [String: Any], terms: [Term]) -> [String]? {
        switch body["action"] as? String {
        case "set":
            guard let name = safeName(body["name"]) else { return nil }
            var out = ["machine", "set", name]
            if let ready = body["ready"] {
                guard let r = ready as? String, ["on", "off"].contains(r) else { return nil }
                out += ["--ready", r]
            }
            if let tier = body["tier"] {
                guard let t = tier as? String, ["heavy", "light"].contains(t) else { return nil }
                out += ["--tier", t]
            }
            if let slots = body["slots"] {
                guard let n = (slots as? NSNumber)?.intValue, (0...64).contains(n) else { return nil }
                out += ["--slots", String(n)]
            }
            return out.count > 3 ? out : nil
        case "suggest":
            guard let team = safeName(body["team"]) else { return nil }
            return ["machine", "suggest", "--team", team]
        case "clone":
            guard let name = safeName(body["name"]), let team = safeName(body["team"]),
                  let url = clean(body["url"], max: 512), let path = clean(body["path"], max: 1024),
                  path.hasPrefix("~/") || (path.hasPrefix("/") && !path.hasPrefix("//")) else { return nil }
            return ["machine", "clone", name, "--team", team, "--url", url, "--path", path]
        case "unlink":
            guard let name = safeName(body["name"]), let team = safeName(body["team"]) else { return nil }
            return ["machine", "unlink", name, "--team", team]
        default:
            return nil
        }
    }

    /// A clone may take minutes on a big repo; the rest only edits a small file.
    public static func timeout(_ argv: [String]) -> TimeInterval {
        argv.count > 1 && argv[1] == "clone" ? 960 : 20
    }
}
