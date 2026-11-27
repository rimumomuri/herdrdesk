import Foundation

// Agent recovery: the app remembers which coding-agent conversation runs where, and after a reboot resumes exactly
// those conversations. It never replays work, never types into a shell, and never resumes anything it cannot verify.

public struct RecoveryLocation: Codable, Equatable {
    public var space: String
    public var tab: String?
    public init(space: String, tab: String?) { self.space = space; self.tab = tab }
}

public struct RecoveryRole: Codable, Equatable {
    public var key: String
    public var title: String
    public var machine: String?
    public var agent: String            // "codex" or "claude-code"
    public var sessionId: String
    public var sessionFile: String?
    public var cwd: String
    public var name: String?
    public var labels: [String: String]
    public var parentRole: String?
    public var lastAddress: String
    public var location: RecoveryLocation?
    /// It was running without approval prompts; it is resumed the same way, never otherwise.
    public var bypass: Bool
    public var savedAt: String
}

public struct RecoveryRegistry: Codable, Equatable {
    public var version = 1
    public var savedAt: String?
    public var roles: [RecoveryRole] = []
    public init(roles: [RecoveryRole] = [], savedAt: String? = nil) { self.roles = roles; self.savedAt = savedAt }
}

/// One terminal as the core and the read-only probe see it right now.
public struct ObservedTerminal: Equatable {
    public var address: String
    public var name: String?
    public var labels: [String: String]
    public var cwd: String?
    public var parent: String?
    public var argv: [String]
    /// Codex / Claude Code when that is the foreground program, otherwise nil.
    public var agent: String?
    public var shell: Bool
    public var sessionId: String?
    public var sessionFile: String?
    public var location: RecoveryLocation?
    public var machine: String? { Recovery.machine(of: address) }
    public var launching: Bool { !(labels["recovery.launching"] ?? "").isEmpty }
    public init(address: String, name: String? = nil, labels: [String: String] = [:], cwd: String? = nil, parent: String? = nil,
                argv: [String] = [], agent: String? = nil, shell: Bool = false, sessionId: String? = nil, sessionFile: String? = nil,
                location: RecoveryLocation? = nil) {
        self.address = address; self.name = name; self.labels = labels; self.cwd = cwd; self.parent = parent; self.argv = argv
        self.agent = agent; self.shell = shell; self.sessionId = sessionId; self.sessionFile = sessionFile; self.location = location
    }
}

public struct RecoveryRuntime: Equatable {
    public var terminals: [ObservedTerminal]
    /// Remote machines that answered. The local machine is always reachable.
    public var connected: Set<String>
    /// Herdr spaces and tabs that exist now (empty when the Herdr app is not installed).
    public var spaces: Set<String>
    public var tabs: Set<String>
    /// The Herdr app answered, so `spaces` is the real list (possibly empty), not just unknown.
    public var layoutKnown = false
    public init(terminals: [ObservedTerminal], connected: Set<String> = [], spaces: Set<String> = [], tabs: Set<String> = []) {
        self.terminals = terminals; self.connected = connected; self.spaces = spaces; self.tabs = tabs
    }
    func online(_ machine: String?) -> Bool { machine.map { connected.contains($0) } ?? true }
    func terminal(_ address: String) -> ObservedTerminal? { terminals.first { $0.address == address } }
}

public enum RecoveryAction: String, Codable {
    case offline, create, pending, blocked, skip, resume, submitted
}

public struct RecoveryPlanItem: Codable, Equatable {
    public var key: String
    public var title: String
    public var terminal: String?
    public var action: RecoveryAction
    public var reason: String
}

public struct RecoveryError: Error, Equatable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

public enum Recovery {
    public static let label = "recovery.role"
    static let agents: Set<String> = ["codex", "claude-code"]
    static let shells: Set<String> = ["sh", "zsh", "bash", "fish", "dash"]
    static let uuid = try! NSRegularExpression(pattern: "^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$")

    public static func isUUID(_ text: String) -> Bool {
        uuid.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    public static func machine(of address: String) -> String? {
        address.contains("/") ? String(address.split(separator: "/", maxSplits: 1)[0]) : nil
    }

    /// A worker started for one task card: short-lived, so never saved for recovery.
    public static func isCardWorker(_ labels: [String: String]) -> Bool {
        let role = labels[label] ?? ""
        if role.range(of: #"-(planner|builder|verifier|researcher|designer|user-tester)-\d+$"#, options: .regularExpression) != nil { return true }
        let teamRole = labels["team.role"] ?? ""
        return !(labels["task.spawned"] ?? "").isEmpty && !teamRole.isEmpty && teamRole != "lead"
    }

    /// Whether the running command skipped approval prompts (so the resume does the same). Only real options count:
    /// the words of a shell's `-c` command are read as a shell would split them, and a prompt that merely names a flag
    /// stays one argument and never matches.
    public static func bypass(_ argv: [String]) -> Bool {
        let flags: Set<String> = ["--dangerously-bypass-approvals-and-sandbox", "--dangerously-skip-permissions"]
        return !options(argv, depth: 0).isDisjoint(with: flags)
    }

    static func options(_ argv: [String], depth: Int) -> Set<String> {
        var result = Set<String>()
        var index = 0
        while index < argv.count {
            let word = argv[index]
            let shellCommand = word.range(of: #"^-[a-z]*c[a-z]*$"#, options: .regularExpression) != nil
                && index > 0 && shells.contains(URL(fileURLWithPath: argv[index - 1]).lastPathComponent)
            if shellCommand, index + 1 < argv.count, depth < 4 {
                result.formUnion(options(shellWords(argv[index + 1]), depth: depth + 1))
                index += 2
                continue
            }
            result.insert(word)
            index += 1
        }
        return result
    }

    /// Splits a command line the way sh does for quotes and backslashes (no expansion).
    static func shellWords(_ line: String) -> [String] {
        var words: [String] = [], current = "", inWord = false
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            switch c {
            case "'":
                inWord = true
                while let q = chars.popFirst(), q != "'" { current.append(q) }
            case "\"":
                inWord = true
                while let q = chars.popFirst(), q != "\"" {
                    if q == "\\", let next = chars.popFirst() { current.append(next) } else { current.append(q) }
                }
            case "\\":
                inWord = true
                if let next = chars.popFirst() { current.append(next) }
            case " ", "\t", "\n", ";", "&", "|":
                if inWord { words.append(current); current = ""; inWord = false }
            default:
                inWord = true; current.append(c)
            }
        }
        if inWord { words.append(current) }
        return words
    }

    /// What to do with a saved role, given the terminal that holds it now (same rules as herdr-recover).
    public static func choose(_ role: RecoveryRole, _ actual: ObservedTerminal?, online: Bool) -> (RecoveryAction, String) {
        guard online else { return (.offline, "machine is not connected; left untouched") }
        guard let actual else { return (.create, "no terminal holds it; resume it in a new terminal") }
        // A verified match counts as running even while it still carries the launch mark of its own resume.
        if actual.agent == role.agent, actual.sessionId == role.sessionId { return (.skip, "the same conversation is already running") }
        if actual.launching { return (.pending, "a resume was already started; check its startup screen first") }
        if actual.agent != nil { return (.blocked, "a different or unverified conversation runs there") }
        if actual.shell { return (.resume, "only a shell is left; resume the exact conversation") }
        return (.blocked, "the foreground program is not a plain shell")
    }

    /// The terminal that holds a role now. Throws when the answer is ambiguous.
    public static func resolve(_ role: RecoveryRole, in runtime: RecoveryRuntime) throws -> (ObservedTerminal?, Bool) {
        guard runtime.online(role.machine) else { return (nil, false) }
        let mine = runtime.terminals.filter { $0.machine == role.machine }
        let matches = mine.filter { $0.sessionId == role.sessionId }
        if matches.count > 1 { throw RecoveryError("the conversation is open more than once: \(role.key)") }
        var candidates = mine.filter { $0.labels[label] == role.key }
        // An exact running session wins over the shell left behind.
        if let match = matches.first, candidates.allSatisfy({ $0.address == match.address || $0.shell }) { return (match, true) }
        if candidates.count > 1 { throw RecoveryError("several terminals claim \(role.key)") }
        if candidates.isEmpty, let same = runtime.terminal(role.lastAddress), same.machine == role.machine, same.sessionId == role.sessionId {
            candidates = [same]
        }
        if candidates.isEmpty { candidates = matches }
        // Nothing claims it by label or session: the terminal at its saved address still counts when it is an agent that
        // could not be verified (never start a second copy) or an unlabelled shell left behind.
        if candidates.isEmpty, let same = runtime.terminal(role.lastAddress), same.machine == role.machine,
           (same.agent != nil && same.sessionId == nil) || (same.shell && same.labels[label] == nil) {
            candidates = [same]
        }
        return (candidates.first, true)
    }

    // MARK: saving

    static func savable(_ terminal: ObservedTerminal) -> Bool {
        guard let agent = terminal.agent, agents.contains(agent), let sid = terminal.sessionId, isUUID(sid),
              let cwd = terminal.cwd, cwd.hasPrefix("/") else { return false }
        return !isCardWorker(terminal.labels)
    }

    static func key(for terminal: ObservedTerminal) -> String {
        if let role = terminal.labels[label], !role.isEmpty { return role }
        return (terminal.machine ?? "local") + ":" + (terminal.sessionId ?? "")
    }

    static func role(for terminal: ObservedTerminal, key: String, among observed: [ObservedTerminal], now: String) -> RecoveryRole {
        let kept = terminal.labels.filter { $0.key.hasPrefix("team.") || [label, "herdr.space", "herdr.tab", "display.title"].contains($0.key) }
        let title = terminal.labels["display.title"] ?? terminal.name ?? terminal.labels["team.title"] ?? key
        let parent = terminal.parent.flatMap { address in observed.first { $0.address == address } }.flatMap { savable($0) ? Recovery.key(for: $0) : nil }
        return RecoveryRole(key: key, title: title, machine: terminal.machine, agent: terminal.agent ?? "", sessionId: terminal.sessionId ?? "",
                            sessionFile: terminal.sessionFile, cwd: terminal.cwd ?? "", name: terminal.name, labels: kept, parentRole: parent,
                            lastAddress: terminal.address, location: terminal.location, bypass: bypass(terminal.argv), savedAt: now)
    }

    /// Automatic save: add or update every verified running agent; drop a role only when it was seen running earlier in
    /// this same live connection and has gone since (closed on purpose). After a reboot nothing has been seen yet, so the
    /// shells left behind keep their roles. Roles on a machine that did not answer are never touched.
    /// Returns the new registry and the keys seen running so far in this connection.
    public static func merge(_ registry: RecoveryRegistry, runtime: RecoveryRuntime, seen: Set<String>, now: String) -> (RecoveryRegistry, Set<String>) {
        let observed = runtime.terminals.filter(savable)
        var byKey: [String: [ObservedTerminal]] = [:]
        for terminal in observed { byKey[key(for: terminal), default: []].append(terminal) }
        var roles: [RecoveryRole] = []
        var fresh = Set<String>()        // keys taken from what runs now
        // What was seen on a machine that is not connected now no longer counts: it may come back rebooted.
        var seenNow = seen.filter { key in registry.roles.first { $0.key == key }.map { runtime.online($0.machine) } ?? true }
        var handled = Set<String>()
        for old in registry.roles {
            handled.insert(old.key)
            if let found = byKey[old.key] {
                guard found.count == 1 else { roles.append(old); continue }   // ambiguous: keep what was saved
                var updated = role(for: found[0], key: old.key, among: runtime.terminals, now: now)
                if !runtime.layoutKnown { updated.location = old.location }   // the Herdr app did not answer this time
                // A lead that is not running right now (still starting, or not resumed yet) keeps its place.
                if updated.parentRole == nil, let parent = old.parentRole, registry.roles.contains(where: { $0.key == parent }) {
                    updated.parentRole = parent
                }
                if updated.sameSave(as: old) { updated.savedAt = old.savedAt }
                roles.append(updated)
                fresh.insert(old.key)
                seenNow.insert(old.key)
            } else if !runtime.online(old.machine) || !seenNow.contains(old.key) {
                roles.append(old)
            } else if runtime.terminals.contains(where: { $0.machine == old.machine && $0.shell
                                                         && ($0.labels[label] == old.key || ($0.labels[label] == nil && $0.address == old.lastAddress)) }) {
                roles.append(old)
            } else if runtime.terminals.contains(where: { $0.machine == old.machine && $0.sessionId == old.sessionId }) {
                roles.append(old)                                             // still running, only not verifiable now
            } else if runtime.terminals.contains(where: { $0.machine == old.machine && $0.agent != nil && $0.sessionId == nil
                                                         && ($0.labels[label] == old.key || $0.address == old.lastAddress) }) {
                roles.append(old)                                             // its agent runs, but its session could not be read
            }
        }
        for (key, found) in byKey.sorted(by: { $0.key < $1.key }) where !handled.contains(key) && found.count == 1 {
            roles.append(role(for: found[0], key: key, among: runtime.terminals, now: now))
            fresh.insert(key)
            seenNow.insert(key)
        }
        // Two keys for one conversation: what runs now wins over an older entry (a renamed role), else the first.
        var sessions = Set<String>()
        let current = roles.filter { fresh.contains($0.key) && sessions.insert(($0.machine ?? "") + "|" + $0.sessionId).inserted }
        let older = roles.filter { !fresh.contains($0.key) && sessions.insert(($0.machine ?? "") + "|" + $0.sessionId).inserted }
        let keep = Set((current + older).map(\.key))
        roles = roles.filter { keep.contains($0.key) }
        var result = RecoveryRegistry(roles: roles, savedAt: registry.savedAt)
        if result.roles != registry.roles { result.savedAt = now }
        return (result, seenNow)
    }

    // MARK: restoring

    /// Parents first, so a resumed worker can be attached to its resumed lead.
    public static func ordered(_ roles: [RecoveryRole]) -> [RecoveryRole] {
        let byKey = Dictionary(roles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [RecoveryRole] = [], done = Set<String>(), visiting = Set<String>()
        func add(_ role: RecoveryRole) {
            if done.contains(role.key) || visiting.contains(role.key) { return }
            visiting.insert(role.key)
            if let parent = role.parentRole.flatMap({ byKey[$0] }) { add(parent) }
            visiting.remove(role.key); done.insert(role.key); result.append(role)
        }
        roles.forEach(add)
        return result
    }

    /// `valid` checks that the working folder and the conversation file still exist (the probe does it on the right machine).
    public static func plan(_ registry: RecoveryRegistry, runtime: RecoveryRuntime, valid: (RecoveryRole) -> String?) -> [RecoveryPlanItem] {
        ordered(registry.roles).map { role in
            do {
                let (actual, online) = try resolve(role, in: runtime)
                var (action, reason) = choose(role, actual, online: online)
                if action == .create || action == .resume {
                    if let problem = valid(role) { (action, reason) = (.blocked, problem) }
                    else if let location = role.location, runtime.layoutKnown, !runtime.spaces.contains(location.space) {
                        (action, reason) = (.blocked, "its Herdr space is gone; open the space again first")
                    }
                }
                return RecoveryPlanItem(key: role.key, title: role.title, terminal: actual?.address, action: action, reason: reason)
            } catch {
                return RecoveryPlanItem(key: role.key, title: role.title, terminal: nil, action: .blocked, reason: "\(error)")
            }
        }
    }

    public static func message(_ locale: String) -> String {
        switch locale {
        case "ko": return "기존 대화 복구입니다. 현재 역할 지침을 다시 확인하고 이전 작업 상태와 미완료·막힘을 짧게 보고하세요. "
            + "완료한 작업·테스트·배포를 자동으로 다시 실행하지 말고 새 지시를 기다리세요. 터미널 주소가 바뀌었을 수 있으니 예전 주소로 전달하지 마세요."
        case "ja": return "既存の会話の復旧です。現在の役割の指示を確認し、以前の作業状態と未完了・停止中の点を短く報告してください。"
            + "完了した作業・テスト・デプロイを自動で再実行せず、新しい指示を待ってください。ターミナルのアドレスが変わった可能性があるため、古いアドレスへ送らないでください。"
        default: return "This is a recovery of your earlier conversation. Re-read your role instructions and briefly report the state of earlier work, "
            + "what is unfinished and what is blocked. Do not re-run finished work, tests or deploys on your own; wait for new instructions. "
            + "Terminal addresses may have changed, so do not send to old addresses."
        }
    }

    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The only command a recovery ever starts: an exact-session resume in the saved folder.
    public static func resumeCommand(_ role: RecoveryRole, locale: String) throws -> String {
        guard isUUID(role.sessionId) else { throw RecoveryError("invalid session id") }
        guard role.cwd.hasPrefix("/") else { throw RecoveryError("invalid working folder") }
        let args: [String]
        switch role.agent {
        case "codex":
            args = ["codex", "--no-daemon"] + (role.bypass ? ["--dangerously-bypass-approvals-and-sandbox"] : []) + ["resume", role.sessionId, message(locale)]
        case "claude-code":
            args = ["claude"] + (role.bypass ? ["--dangerously-skip-permissions"] : []) + ["--resume", role.sessionFile ?? role.sessionId, message(locale)]
        default:
            throw RecoveryError("unsupported agent")
        }
        return "cd -- " + quote(role.cwd) + " && exec " + args.map(quote).joined(separator: " ")
    }

    /// `hc run` arguments that resume one role, placed in its saved space and tab when they still exist.
    public static func runArguments(_ role: RecoveryRole, runtime: RecoveryRuntime, parent: String?, locale: String, now: String) throws -> [String] {
        var args = ["run", "--bg", "--keep", "--json", "--cwd", role.cwd]
        args += parent.map { ["--parent", $0, "--outlive-parent"] } ?? ["--no-parent"]
        if let machine = role.machine { args += ["--on", machine] }
        if let name = role.name, !name.isEmpty, !runtime.terminals.contains(where: { $0.name == name }) { args += ["--name", name] }
        var labels = role.labels
        labels[label] = role.key
        labels["recovery.launching"] = role.sessionId
        labels["recovery.launching-at"] = now
        labels["herdr.space"] = nil; labels["herdr.tab"] = nil
        if let location = role.location, runtime.spaces.contains(location.space) {
            let prefix = role.machine.map { $0 + "/" } ?? ""
            labels["herdr.space"] = location.space.hasPrefix(prefix) ? String(location.space.dropFirst(prefix.count)) : location.space
            if let tab = location.tab, runtime.tabs.contains(tab) {
                labels["herdr.tab"] = tab.hasPrefix(prefix) ? String(tab.dropFirst(prefix.count)) : tab
            }
        }
        for (key, value) in labels.sorted(by: { $0.key < $1.key }) { args += ["--label", key + "=" + value] }
        return args + ["--", "/bin/zsh", "-lic", try resumeCommand(role, locale: locale)]
    }
}

extension RecoveryRole {
    func sameSave(as other: RecoveryRole) -> Bool {
        var a = self, b = other
        a.savedAt = ""; b.savedAt = ""
        return a == b
    }
}

extension Recovery {
    /// The labels a saved role keeps, as text: a change to them is a reason to save again.
    public static func labelSignature(_ labels: [String: String]) -> String {
        labels.filter { $0.key.hasPrefix("team.") || [label, "herdr.space", "herdr.tab", "display.title"].contains($0.key) }
            .sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: ",")
    }

    /// When to save again: soon after the first look of a connection (even with no agent running, so a reboot is noticed),
    /// a few seconds after agents start, end or move, and at most once a minute when only their turns advanced (a new
    /// conversation inside the same agent shows up there). Nil: nothing to do.
    public static func saveDelay(checked: Bool, structural: Bool, turns: Bool, sinceLast: TimeInterval) -> TimeInterval? {
        if !checked { return 2 }
        if structural { return 5 }
        if turns { return max(5, 60 - sinceLast) }
        return nil
    }
}
