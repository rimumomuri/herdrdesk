import Foundation

/// Display-only metadata. A global default is never promoted to a running model.
public enum ModelOptions {
    static func clean(_ x: Any?) -> String? {
        guard let s = x as? String, !s.isEmpty, s.count <= 120,
              s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return s
    }
    public static func launch(_ argv: [String]) -> [String: String] {
        var i = 0
        if argv.first.map({ URL(fileURLWithPath: $0).lastPathComponent }) == "env" {
            i = 1
            while i < argv.count && argv[i].contains("=") && !argv[i].hasPrefix("-") { i += 1 }
        }
        guard i < argv.count, ["codex", "claude"].contains(URL(fileURLWithPath: argv[i]).lastPathComponent) else { return [:] }
        let codex = URL(fileURLWithPath: argv[i]).lastPathComponent == "codex"
        i += 1
        var result: [String: String] = [:]
        var flags: [String: String] = [:]
        while i < argv.count {
            let a = argv[i]
            if a == "--" || !a.hasPrefix("-") { break } // prompt text is never parsed
            if ["--model", "-m", "--effort"].contains(a), i + 1 < argv.count {
                if let v = clean(argv[i + 1]) { flags[a == "--effort" ? "effort" : "model"] = v }
                i += 2; continue
            }
            if a.hasPrefix("--model=") { flags["model"] = clean(String(a.dropFirst(8))); i += 1; continue }
            if a.hasPrefix("--effort=") { flags["effort"] = clean(String(a.dropFirst(9))); i += 1; continue }
            if codex && (a == "-c" || a == "--config"), i + 1 < argv.count {
                let pair = argv[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2, ["model", "model_reasoning_effort"].contains(pair[0]) {
                    result[pair[0] == "model" ? "model" : "effort"] = clean(pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")))
                }
                i += 2; continue
            }
            if ["-s", "--sandbox", "-C", "--cd", "--profile", "-p", "--permission-mode", "--settings"].contains(a) { i += 2; continue }
            // Unknown option arity: do not scan beyond it into a possible prompt.
            if !["--no-daemon", "--no-alt-screen", "--dangerously-bypass-approvals-and-sandbox", "--dangerously-skip-permissions"].contains(a) && !(a == "-c" && !codex) { break }
            i += 1
        }
        return result.merging(flags) { _, flag in flag }
    }
    public static func defaults(app: String, home: URL) -> [String: String] {
        if app == "codex", let s = try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8) {
            var out: [String: String] = [:]
            // This is deliberately NOT a general TOML parser. Read only a leading run of
            // simple, allowlisted root scalars. Stop at any other construct: in particular
            // never scan developer instructions, multiline strings, arrays or profile tables.
            let simple = try! NSRegularExpression(pattern: #"^(model|model_reasoning_effort)\s*=\s*"([A-Za-z0-9_.:/+\-]{1,120})"\s*(?:#.*)?$"#)
            for line in s.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") { continue }
                guard let m = simple.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                      let kr = Range(m.range(at: 1), in: t), let vr = Range(m.range(at: 2), in: t) else { break }
                let key = String(t[kr]) == "model" ? "model" : "effort"
                if out[key] != nil { return [:] } // invalid duplicate keys: no inferred defaults
                out[key] = String(t[vr])
            }
            return out
        }
        if app == "claude-code", let d = try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json")),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            var out: [String: String] = [:]
            out["model"] = clean(o["model"]); out["effort"] = clean(o["effortLevel"])
            return out
        }
        return [:]
    }
    static let localDefaults: [String: [String: String]] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Fixture runs must not read the operator's settings.
        if ProcessInfo.processInfo.environment["HERDRDESK_HC"] != nil { return [:] }
        return Dictionary(uniqueKeysWithValues: ["codex", "claude-code"].map { ($0, defaults(app: $0, home: home)) })
    }()
}
