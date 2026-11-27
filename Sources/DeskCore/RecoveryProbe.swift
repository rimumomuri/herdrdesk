import Foundation

// Read-only look at which conversation each agent terminal holds. It reads process lists, the small session record
// Claude Code keeps per process (only its session id), which Codex session files a process has open, and the session
// id on the first line of those files. Conversation contents are never read or moved.

public struct RecoveryProbe {
    public typealias Processes = [Int: (ppid: Int, command: String)]

    // MARK: scripts (each runs as `hc exec [--on machine] /bin/sh -c <script>`)

    public static let processScript = "ps -axo pid=,ppid=,comm="

    static func quote(_ text: String) -> String { Recovery.quote(text) }

    /// Claude: the session id in `~/.claude/sessions/<pid>.json`. Codex: the session files its process (and its own
    /// codex children) have open.
    public static func sessionScript(claude: [Int], codex: [Int: [Int]]) -> String {
        var lines: [String] = []
        for pid in claude.sorted() {
            let file = "\"$HOME/.claude/sessions/\(pid).json\""
            lines.append("printf '@claude %s\\n' \(pid); [ -f \(file) ] && grep -o '\"sessionId\":\"[0-9a-f-]*\"' \(file) | head -n 1; [ -f \(file) ] && grep -o '\"pid\":[0-9]*' \(file) | head -n 1")
        }
        for (pid, ids) in codex.sorted(by: { $0.key < $1.key }) {
            let list = ids.sorted().map(String.init).joined(separator: ",")
            lines.append("printf '@codex %s\\n' \(pid); /usr/sbin/lsof -p \(list) -Fn 2>/dev/null | grep '^n.*/\\.codex/sessions/.*\\.jsonl$'")
        }
        return (lines + ["true"]).joined(separator: "\n")
    }

    /// Codex: the session id on the first line of each open file. Claude: where each conversation file is.
    public static func fileScript(codexFiles: [String], claudeSessions: [String]) -> String {
        var lines: [String] = []
        for file in Set(codexFiles).sorted() where !file.contains("\n") {
            lines.append("printf '@file %s\\n' \(quote(file)); head -n 1 \(quote(file)) | grep -o '\"type\":\"session_meta\"' | head -n 1; head -n 1 \(quote(file)) | grep -o '\"id\":\"[0-9a-f-]\\{36\\}\"' | head -n 1")
        }
        for sid in Set(claudeSessions).sorted() where Recovery.isUUID(sid) {
            lines.append("printf '@sid %s\\n' \(sid); ls -1 \"$HOME\"/.claude/projects/*/\(sid).jsonl 2>/dev/null")
        }
        return (lines + ["true"]).joined(separator: "\n")
    }

    /// For each role: does its folder exist, does its conversation file exist, and (Codex) does the file carry its id.
    public static func validateScript(_ roles: [RecoveryRole]) -> String {
        roles.enumerated().map { index, role in
            var line = "printf '@valid %s\\n' \(index); [ -d \(quote(role.cwd)) ] && echo dir"
            if let file = role.sessionFile, !file.contains("\n") {
                line += "; [ -f \(quote(file)) ] && echo file"
                if role.agent == "codex" { line += "; head -n 1 \(quote(file)) | grep -o '\"id\":\"[0-9a-f-]\\{36\\}\"' | head -n 1" }
            }
            return line
        }.joined(separator: "\n") + "\ntrue"   // a false last test must not hide the other roles' answers
    }

    // MARK: parsing

    public static func parseProcesses(_ text: String) -> Processes {
        var result: Processes = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { continue }
            result[pid] = (ppid, String(parts[2]))
        }
        return result
    }

    /// `@tag value` headers, each followed by its lines.
    public static func sections(_ text: String) -> [(tag: String, value: String, lines: [String])] {
        var result: [(String, String, [String])] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("@"), let space = line.firstIndex(of: " ") {
                result.append((String(line[line.index(after: line.startIndex)..<space]), String(line[line.index(after: space)...]), []))
            } else if !line.isEmpty, !result.isEmpty {
                result[result.count - 1].2.append(line)
            }
        }
        return result.map { (tag: $0.0, value: $0.1, lines: $0.2) }
    }

    static func quoted(_ line: String, key: String) -> String? {
        guard let range = line.range(of: "\"\(key)\":\"") else { return nil }
        let rest = line[range.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    /// Claude session ids per pid; the record must name the same pid.
    public static func parseClaude(_ text: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for section in sections(text) where section.tag == "claude" {
            guard let pid = Int(section.value),
                  let sid = section.lines.lazy.compactMap({ quoted($0, key: "sessionId") }).first, Recovery.isUUID(sid),
                  section.lines.contains("\"pid\":\(pid)") else { continue }
            result[pid] = sid
        }
        return result
    }

    public static func parseCodexFiles(_ text: String) -> [Int: [String]] {
        var result: [Int: [String]] = [:]
        for section in sections(text) where section.tag == "codex" {
            guard let pid = Int(section.value) else { continue }
            result[pid] = section.lines.filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
        }
        return result
    }

    /// Codex file -> session id (only files whose first line is a session record); Claude id -> conversation files.
    public static func parseFiles(_ text: String) -> (codex: [String: String], claude: [String: [String]]) {
        var codex: [String: String] = [:], claude: [String: [String]] = [:]
        for section in sections(text) {
            if section.tag == "file", section.lines.contains("\"type\":\"session_meta\""),
               let sid = section.lines.lazy.compactMap({ quoted($0, key: "id") }).first, Recovery.isUUID(sid) {
                codex[section.value] = sid
            } else if section.tag == "sid" {
                claude[section.value] = section.lines.filter { $0.hasSuffix(".jsonl") }
            }
        }
        return (codex, claude)
    }

    /// The problem with each role's saved files, or nil when they are in place.
    public static func parseValidation(_ text: String, roles: [RecoveryRole]) -> [Int: String?] {
        var result: [Int: String?] = [:]
        for section in sections(text) where section.tag == "valid" {
            guard let index = Int(section.value), roles.indices.contains(index) else { continue }
            let role = roles[index]
            if !section.lines.contains("dir") { result[index] = "its working folder is missing"; continue }
            if role.sessionFile != nil, !section.lines.contains("file") { result[index] = "its conversation file is missing"; continue }
            if role.agent == "codex", role.sessionFile != nil,
               section.lines.lazy.compactMap({ quoted($0, key: "id") }).first != role.sessionId {
                result[index] = "its conversation file belongs to another session"; continue
            }
            result[index] = .some(nil)
        }
        return result
    }

    /// The Claude conversation file for a session: the one under the project folder of its working folder, or the only one.
    public static func claudeFile(_ files: [String], cwd: String?) -> String? {
        let expected = (cwd ?? "").map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let preferred = files.filter { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent == expected }
        if preferred.count == 1 { return preferred[0] }
        return files.count == 1 ? files[0] : nil
    }
}

/// Collects the current picture from Core, the Herdr app and each machine's probe.
public struct RecoveryCollector {
    let hc: HcRunning
    let app: HcRunning?
    public init(hc: HcRunning, app: HcRunning?) { self.hc = hc; self.app = app }

    func json(_ runner: HcRunning, _ args: [String], timeout: TimeInterval = 15) -> [String: Any]? {
        let result = runner.run(args, timeout: timeout)
        guard result.code == 0, !result.timedOut, let data = result.out.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `hc exec` on a machine (nil = here). Nil when it did not answer.
    public func shell(_ machine: String?, _ script: String) -> String? {
        let result = hc.run(["exec"] + (machine.map { ["--on", $0] } ?? []) + ["--timeout", "30", "/bin/sh", "-c", script], timeout: 40)
        return result.code == 0 && !result.timedOut ? result.out : nil
    }

    public func collect() throws -> RecoveryRuntime {
        guard let listing = json(hc, ["ls", "--json"]), let rows = listing["terminals"] as? [[String: Any]] else {
            throw RecoveryError("Herdr Core did not answer")
        }
        var connected = Set((json(hc, ["machine", "ls", "--json"])?["machines"] as? [[String: Any]] ?? [])
            .filter { $0["state"] as? String == "connected" }.compactMap { $0["name"] as? String })
        var spaces = Set<String>(), tabs = Set<String>(), locations: [String: RecoveryLocation] = [:], layoutKnown = false
        if let app, let layout = json(app, ["ls"])?["spaces"] as? [[String: Any]] {
            layoutKnown = true
            for space in layout {
                guard let id = space["id"] as? String else { continue }
                spaces.insert(id)
                for tab in space["tabs"] as? [[String: Any]] ?? [] {
                    let tabId = tab["id"] as? String
                    if let tabId { tabs.insert(tabId) }
                    for terminal in tab["terminals"] as? [[String: Any]] ?? [] {
                        if let address = terminal["terminal"] as? String { locations[address] = RecoveryLocation(space: id, tab: tabId) }
                    }
                }
            }
        }
        struct Row { var term: ObservedTerminal; var pid: Int? }
        var byMachine: [String?: [Row]] = [:]
        for row in rows where (row["state"] as? String ?? "live") == "live" {
            guard let address = row["address"] as? String else { continue }
            let machine = Recovery.machine(of: address)
            if let machine, !connected.contains(machine) { continue }
            guard let detail = json(hc, ["get", address, "--json"]) else {
                if let machine { connected.remove(machine); continue }
                throw RecoveryError("Herdr Core did not describe \(address)")
            }
            let program = row["agent"] as? String
            let foreground = detail["foreground"] as? [String: Any]
            var term = ObservedTerminal(address: address, name: detail["name"] as? String,
                                        labels: detail["labels"] as? [String: String] ?? [:],
                                        cwd: foreground?["cwd"] as? String ?? detail["cwd"] as? String,
                                        parent: detail["parent"] as? String, argv: detail["argv"] as? [String] ?? [],
                                        agent: program.flatMap { Recovery.agents.contains($0) ? $0 : nil }, location: locations[address])
            term.shell = false
            byMachine[machine, default: []].append(Row(term: term, pid: (foreground?["pid"] as? NSNumber)?.intValue))
        }
        var terminals: [ObservedTerminal] = []
        for (machine, rows) in byMachine {
            guard let processText = shell(machine, RecoveryProbe.processScript) else {
                if let machine { connected.remove(machine); continue }
                throw RecoveryError("cannot list processes")
            }
            let processes = RecoveryProbe.parseProcesses(processText)
            var claude: [Int] = [], codex: [Int: [Int]] = [:]
            for row in rows {
                guard let pid = row.pid else { continue }
                if row.term.agent == "claude-code" { claude.append(pid) }
                if row.term.agent == "codex" {
                    codex[pid] = [pid] + processes.filter { $0.value.ppid == pid && URL(fileURLWithPath: $0.value.command).lastPathComponent == "codex" }.map(\.key)
                }
            }
            let sessionText = shell(machine, RecoveryProbe.sessionScript(claude: claude, codex: codex)) ?? ""
            let claudeIds = RecoveryProbe.parseClaude(sessionText), codexFiles = RecoveryProbe.parseCodexFiles(sessionText)
            let fileText = shell(machine, RecoveryProbe.fileScript(codexFiles: codexFiles.values.flatMap { $0 }, claudeSessions: Array(claudeIds.values))) ?? ""
            let files = RecoveryProbe.parseFiles(fileText)
            for row in rows {
                var term = row.term
                if let pid = row.pid {
                    let command = URL(fileURLWithPath: processes[pid]?.command ?? "").lastPathComponent
                    term.shell = term.agent == nil && Recovery.shells.contains(command)
                    if term.agent == "claude-code", let sid = claudeIds[pid] {
                        term.sessionId = sid
                        term.sessionFile = RecoveryProbe.claudeFile(files.claude[sid] ?? [], cwd: term.cwd)
                    } else if term.agent == "codex" {
                        let sessions = Dictionary((codexFiles[pid] ?? []).compactMap { file in files.codex[file].map { ($0, file) } }, uniquingKeysWith: { a, _ in a })
                        if sessions.count == 1, let (sid, file) = sessions.first { term.sessionId = sid; term.sessionFile = file }
                    }
                }
                terminals.append(term)
            }
        }
        var runtime = RecoveryRuntime(terminals: terminals.sorted { $0.address < $1.address }, connected: connected, spaces: spaces, tabs: tabs)
        runtime.layoutKnown = layoutKnown
        return runtime
    }

    /// Checks each role's folder and conversation file on its own machine.
    public func validator(for roles: [RecoveryRole], runtime: RecoveryRuntime) -> (RecoveryRole) -> String? {
        var problems: [String: String?] = [:]
        for (machine, group) in Dictionary(grouping: roles, by: \.machine) where runtime.online(machine) {
            let text = shell(machine, RecoveryProbe.validateScript(group)) ?? ""
            for (index, problem) in RecoveryProbe.parseValidation(text, roles: group) { problems[group[index].key] = problem }
        }
        return { role in problems[role.key] ?? "its files could not be checked" }
    }
}
