import DeskCore
import Foundation

/// Follows only new records from the conversation files of currently bound local agents.
final class LiveChatFeed {
    private struct Binding: Hashable {
        let address: String
        let session: String
        let pid: Int64
        let provider: String
    }

    private final class Source {
        let url: URL
        let cursor: NewChatRecords
        var conversation: LiveChatConversation
        let generation = UUID().uuidString

        init(url: URL, cursor: NewChatRecords, binding: Binding, receipts: UserDispatchReceipts) {
            self.url = url
            self.cursor = cursor
            self.conversation = LiveChatConversation(address:binding.address,session:binding.session,receipts:receipts)
        }
    }

    private let queue = DispatchQueue(label: "herdrdesk.live-chat", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var terms: [Term] = []
    private var sources: [Binding: Source] = [:]
    private var retryDiscovery = Date.distantPast
    private let receive: ([[String: String]]) -> Void
    private let receipts: UserDispatchReceipts

    init(receipts: UserDispatchReceipts, receive: @escaping ([[String: String]]) -> Void) {
        self.receive = receive
        self.receipts = receipts
    }

    func track(_ terminals: [Term]) {
        queue.async {
            self.terms = terminals
            if terminals.isEmpty {
                self.retryDiscovery = .distantPast
                self.timer?.cancel()
                self.timer = nil
            } else if self.timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(200))
                timer.setEventHandler { [weak self] in self?.poll() }
                self.timer = timer
                timer.resume()
            }
        }
    }

    private func poll() {
        let eligible = terms.filter { $0.state == "live" && $0.isAgent && $0.role != nil }
        let local = eligible.filter { !$0.address.contains("/") && $0.pid > 0 }
        let bindings = local.compactMap { term -> Binding? in
            guard let provider = term.app else { return nil }
            return Binding(address: term.address, session: term.session, pid: term.pid, provider: provider)
        }
        let current = Set(bindings)
        for binding in Array(sources.keys) where !current.contains(binding) { removeSource(binding) }
        if Date() >= retryDiscovery {
            retryDiscovery = Date().addingTimeInterval(8)
            discover(bindings)
        }

        let time = ISO8601DateFormatter()
        var batch: [[String: String]] = []
        let uniqueRoles = Dictionary(grouping: eligible, by: { $0.role }).filter { $0.value.count == 1 }
        for (binding, source) in sources {
            guard let target = local.first(where: { $0.address == binding.address && $0.session == binding.session }),
                  let role = target.role, uniqueRoles[role] != nil else { continue }
            source.cursor.read { bytes, offset in
                // The sender's own `hc send` call: works even when the target's records are not readable here.
                if let send = LiveChatMessage.outgoingSend(bytes, provider: binding.provider) {
                    let row = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
                    let to = HandoffTarget.resolve(send.target, in: eligible)
                    batch.append(["kind": "agent-send", "id": "send:\(binding.address):\(binding.session):\(offset)",
                                  "at": row?["timestamp"] as? String ?? time.string(from: Date()),
                                  "fromAddress": binding.address, "fromSession": binding.session, "fromRole": role,
                                  "toAddress": to?.address ?? send.target, "toSession": to?.session ?? "", "toRole": to?.role ?? "",
                                  "body": send.body])
                }
                if binding.provider == "codex", let turn = LiveChatMessage.codexTurn(bytes) {
                    _ = source.conversation.consume(bytes, provider: binding.provider)
                    batch.append(["kind": "turn", "turn": turn.id, "state": turn.state, "at": turn.at,
                                  "fromAddress": binding.address, "session": binding.session])
                    return
                }
                guard let message = source.conversation.consume(bytes, provider: binding.provider, recordKey:source.generation + ":" + String(offset)) else { return }
                let row = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
                var entry = ["id": "live:\(binding.address):\(binding.session):\(offset)",
                             "at": row?["timestamp"] as? String ?? time.string(from: Date()), "session": binding.session, "body": message.body]
                if message.kind == "reply" {
                    entry["turn"] = source.conversation.turn
                    entry["turnStartedAt"] = source.conversation.startedAt
                    // Claude end_turn is the final boundary; Codex supplies task_complete separately.
                    if binding.provider == "claude-code" { entry["turnEndedAt"] = entry["at"] }
                }
                if let senderAddress = message.senderAddress {
                    let matches = eligible.filter { $0.address == senderAddress }
                    guard matches.count == 1, let sender = matches.first, let senderRole = sender.role,
                          uniqueRoles[senderRole] != nil, sender.address != target.address, senderRole != role,
                          message.senderName.map({ $0 == sender.name || $0 == senderRole || $0 == sender.labels["display.title"] }) == true else { return }
                    entry["role"] = senderRole
                    entry["recipient"] = role
                    entry["kind"] = "agent-handoff"
                    entry["fromAddress"] = sender.address
                    entry["toAddress"] = target.address
                    entry["fromSession"] = sender.session
                    entry["toSession"] = target.session
                } else {
                    entry["role"] = role
                    entry["kind"] = message.kind
                    entry["fromAddress"] = target.address
                }
                batch.append(entry)
            }
            if source.cursor.invalidated { removeSource(binding) }
        }
        if !batch.isEmpty { receive(batch) }
    }

    private func removeSource(_ binding: Binding) {
        guard let source = sources.removeValue(forKey:binding) else { return }
        try? receipts.rotateObserverEpoch(address:binding.address,session:binding.session,expected:source.conversation.boundObserverEpoch)
    }

    private func discover(_ bindings: [Binding]) {
        guard !bindings.isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths: [Binding: URL] = [:]
        for binding in bindings where binding.provider == "claude-code" {
            let metadata = home.appendingPathComponent(".claude/sessions/\(binding.pid).json")
            guard let bytes = try? Data(contentsOf: metadata), bytes.count < 32 * 1024,
                  let row = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  (row["pid"] as? NSNumber)?.int64Value == binding.pid,
                  let session = row["sessionId"] as? String, UUID(uuidString: session) != nil else { continue }
            let root = home.appendingPathComponent(".claude/projects", isDirectory: true)
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            let files = folders.map { $0.appendingPathComponent(session + ".jsonl") }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if files.count == 1, let file = files.first { paths[binding] = file }
        }

        let codex = bindings.filter { $0.provider == "codex" }
        if !codex.isEmpty {
            let result = ProcessHc(path: "/bin/ps").run(["-axo", "pid=,ppid=,comm="], timeout: 2)
            let processes = result.out.split(separator: "\n").map { $0.split(maxSplits: 2, whereSeparator: \.isWhitespace) }
            var byPID: [Int64: Binding] = [:]
            for binding in codex { byPID[binding.pid] = binding }
            var parents: [Int64: Int64] = [:]
            for row in processes where row.count == 3 {
                guard let pid = Int64(row[0]), let parent = Int64(row[1]) else { continue }
                parents[pid] = parent
            }
            var owners = byPID
            for row in processes where row.count == 3 && URL(fileURLWithPath: String(row[2])).lastPathComponent == "codex" {
                guard let pid = Int64(row[0]) else { continue }
                var ancestor = pid
                for _ in 0..<16 {
                    if let binding = byPID[ancestor] { owners[pid] = binding; break }
                    guard let parent = parents[ancestor], parent > 1, parent != ancestor else { break }
                    ancestor = parent
                }
            }
            let resultFiles = ProcessHc(path: "/usr/sbin/lsof").run(["-a", "-p", owners.keys.map(String.init).joined(separator: ","), "-Fpan"], timeout: 3)
            let root = home.appendingPathComponent(".codex/sessions", isDirectory: true).path + "/"
            var files: [Binding: Set<URL>] = [:]
            var owner: Binding?
            var writable = false
            for record in resultFiles.out.split(separator: "\n") {
                switch record.first {
                case "p": owner = Int64(record.dropFirst()).flatMap { owners[$0] }; writable = false
                case "a": writable = record == "aw" || record == "au"
                case "n" where writable:
                    let path = String(record.dropFirst())
                    if let owner, path.hasPrefix(root), path.hasSuffix(".jsonl") {
                        files[owner, default: []].insert(URL(fileURLWithPath: path))
                    }
                default: break
                }
            }
            for (binding, matches) in files where matches.count == 1 { paths[binding] = matches.first }
        }

        let counts = Dictionary(grouping: paths.values, by: { $0 }).mapValues(\.count)
        let removed = sources.filter { paths[$0.key] != nil && (paths[$0.key] != $0.value.url || counts[$0.value.url] != 1) }.keys
        for binding in Array(removed) { removeSource(binding) }
        for (binding, file) in paths where counts[file] == 1 && sources[binding] == nil {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  file.standardizedFileURL.path == file.resolvingSymlinksInPath().standardizedFileURL.path else { continue }
            if let cursor = NewChatRecords(url: file) { sources[binding] = Source(url: file, cursor: cursor, binding:binding, receipts:receipts) }
        }
    }
}
