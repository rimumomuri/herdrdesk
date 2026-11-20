import Foundation
import Darwin

public struct LiveChatMessage {
    public let body: String
    public let senderAddress: String?
    public let senderName: String?
    public var kind: String = "progress"

    /// Lifecycle records contain execution state, rather than transcript or tool output.
    public static func codexTurn(_ data: Data) -> (id: String, state: String, at: String)? {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              row["type"] as? String == "event_msg",
              let payload = row["payload"] as? [String: Any],
              let id = payload["turn_id"] as? String, !id.isEmpty, id.count <= 96,
              let at = row["timestamp"] as? String, let event = payload["type"] as? String else { return nil }
        switch event {
        case "task_started", "turn_started": return (id, "working", at)
        case "task_complete", "turn_complete", "turn_aborted": return (id, "done", at)
        default: return nil
        }
    }

    /// Accept only typed, user-facing text. Command items, reasoning and tool results never leave this parser.
    public static func parse(_ data: Data, provider: String) -> Self? {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if provider == "codex" {
            guard row["type"] as? String == "response_item",
                  let item = row["payload"] as? [String: Any], item["type"] as? String == "message",
                  let content = item["content"] as? [[String: Any]] else { return nil }
            switch item["role"] as? String {
            case "assistant" where ["commentary", "final", "final_answer"].contains(item["phase"] as? String ?? ""):
                let text = content.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                guard let body = clean(text) else { return nil }
                return Self(body: body, senderAddress: nil, senderName: nil, kind: ["final", "final_answer"].contains(item["phase"] as? String ?? "") ? "reply" : "progress")
            case "user":
                guard content.count == 1, content[0]["type"] as? String == "input_text",
                      let text = content[0]["text"] as? String else { return nil }
                return handoff(text)
            default:
                return nil
            }
        }
        guard provider == "claude-code", row["type"] as? String == "user",
              row["isSidechain"] as? Bool != true, row["isMeta"] as? Bool != true,
              let message = row["message"] as? [String: Any], message["role"] as? String == "user" else { return nil }
        if let text = message["content"] as? String { return handoff(text) }
        guard let content = message["content"] as? [[String: Any]], content.count == 1,
              content[0]["type"] as? String == "text", let text = content[0]["text"] as? String else { return nil }
        return handoff(text)
    }

    /// Claude does not tag commentary. A text block preceding a tool in the same
    /// message is a progress update, while final-only text has no tool block.
    public static func claudeProgress(_ data: Data, pending: inout (id: String, text: String)?) -> Self? {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              row["isSidechain"] as? Bool != true, row["isMeta"] as? Bool != true else { return nil }
        if row["type"] as? String == "user" {
            pending = nil
            return nil
        }
        guard row["type"] as? String == "assistant", let item = row["message"] as? [String: Any],
              item["role"] as? String == "assistant", let id = item["id"] as? String,
              let blocks = item["content"] as? [[String: Any]] else { return nil }
        if pending?.id != id { pending = (id, "") }
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String else { continue }
                let previous = pending?.text ?? ""
                pending = (id, String((previous.isEmpty ? text : previous + "\n" + text).prefix(8192)))
            case "tool_use":
                let text = pending?.text ?? ""
                pending = nil
                if let body = clean(text) { return Self(body: body, senderAddress: nil, senderName: nil) }
            default:
                break
            }
        }
        return nil
    }

    private static func clean(_ text: String) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !body.contains("\u{001B}") else { return nil }
        return String(body.prefix(8192))
    }

    fileprivate static func isRawUserRequest(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in:.whitespacesAndNewlines)
        // An outer HC frame is internal even when malformed or nested. Literal
        // examples inside an otherwise raw user message do not create a frame.
        return !text.isEmpty && text.range(of:#"\A<hc(?:\s|>)"#, options:.regularExpression) == nil
    }

    private static func handoff(_ text: String) -> Self? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Newer envelopes supply a reply address. Older ones supply only the sender.
        let envelope = #"\A<hc from="([A-Za-z0-9._/-]+) ([^"<>\r\n]+)"(?: reach="hc send \1(?: [^"<>\r\n]*)?")?>([\s\S]+)</hc>\z"#
        guard let regex = try? NSRegularExpression(pattern: envelope),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let address = Range(match.range(at: 1), in: text),
              let name = Range(match.range(at: 2), in: text),
              let content = Range(match.range(at: 3), in: text) else { return nil }
        let body = String(text[content])
        guard !body.contains("<hc"), !body.contains("</hc>"), let body = clean(body) else { return nil }
        return Self(body: body, senderAddress: String(text[address]), senderName: String(text[name]))
    }
}

/// A forward-only reader. Files start at EOF and incomplete lines wait for the next poll.
public final class NewChatRecords {
    private let file: FileHandle
    private var pending = Data()
    private var offset: UInt64
    private var discard = false
    private let url: URL
    private var observedTail = Data()
    public private(set) var invalidated = false

    public init?(url: URL) {
        guard let file = try? FileHandle(forReadingFrom: url), let offset = try? file.seekToEnd() else { return nil }
        self.file = file
        self.offset = offset
        self.url = url
    }

    public func read(_ accept: (Data, UInt64) -> Void) {
        var opened = stat(), current = stat()
        guard !invalidated, fstat(file.fileDescriptor, &opened) == 0,
              lstat(url.path, &current) == 0, opened.st_dev == current.st_dev,
              opened.st_ino == current.st_ino, current.st_mode & S_IFMT == S_IFREG,
              current.st_size >= offset else { invalidated = true; return }
        // Recheck only bytes this reader already observed after its EOF boundary.
        if !observedTail.isEmpty {
            do {
                try file.seek(toOffset: offset - UInt64(observedTail.count))
                let tail = try file.read(upToCount: observedTail.count)
                try file.seek(toOffset: offset)
                guard tail == observedTail else { invalidated = true; return }
            } catch { invalidated = true; return }
        }
        guard let chunk = try? file.read(upToCount: 256 * 1024), !chunk.isEmpty else { return }
        observedTail = Data((observedTail + chunk).suffix(64))
        for byte in chunk {
            offset += 1
            if byte == 10 {
                if !discard && !pending.isEmpty { accept(pending, offset) }
                pending.removeAll(keepingCapacity: true)
                discard = false
            } else if !discard {
                if pending.count < 512 * 1024 { pending.append(byte) }
                else { pending.removeAll(); discard = true }
            }
        }
    }
}


/// Tracks only records observed after the live reader's EOF boundary. Unknown/internal
/// turns cannot produce user replies. Provider turn IDs are never HC turn counters.
public struct LiveChatConversation {
    public private(set) var turn = ""
    public private(set) var startedAt = ""
    private var userFacing = false
    private var claudePending: (id: String, text: String)?
    private var claudeFinished = false
    private let address: String?
    private let session: String?
    private let receipts: UserDispatchReceipts?
    public let boundObserverEpoch: String?
    public init(address: String? = nil, session: String? = nil, receipts: UserDispatchReceipts? = nil) {
        self.address = address; self.session = session; self.receipts = receipts
        if let receipts, let address, let session {
            boundObserverEpoch = try? receipts.observerEpoch(address:address,session:session)
        } else { boundObserverEpoch = nil }
    }

    private mutating func observeUser(_ text: String, recordKey: String?) -> Bool {
        if UserDispatchReceipts.candidatePayload(text) != nil {
            if let receipts, let address, let session, let recordKey, let epoch = boundObserverEpoch, !turn.isEmpty {
                if receipts.claim(text:text,address:address,session:session,turn:turn,recordKey:recordKey,observerEpoch:epoch) { userFacing = true }
            }
            return true
        }
        if LiveChatMessage.isRawUserRequest(text) && !turn.isEmpty { userFacing = true }
        return false
    }

    public mutating func consume(_ data: Data, provider: String, recordKey: String? = nil) -> LiveChatMessage? {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if provider == "codex" {
            if let signal = LiveChatMessage.codexTurn(data) {
                if signal.state == "working" {
                    turn = signal.id; startedAt = signal.at; userFacing = false
                } else if signal.id == turn {
                    userFacing = false
                    turn = ""; startedAt = ""
                }
            }
            if row["type"] as? String == "response_item",
               let item = row["payload"] as? [String: Any], item["type"] as? String == "message", item["role"] as? String == "user" {
                let blocks = item["content"] as? [[String: Any]] ?? []
                guard blocks.allSatisfy({ ["input_text", "input_image"].contains($0["type"] as? String ?? "") }) else { return nil }
                let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if observeUser(text,recordKey:recordKey) { return nil }
            }
            guard let message = LiveChatMessage.parse(data, provider: provider) else { return nil }
            return message.kind == "reply" && !userFacing ? nil : message
        }
        guard provider == "claude-code", row["isSidechain"] as? Bool != true,
              row["isMeta"] as? Bool != true else { return nil }
        if row["type"] as? String == "user", let item = row["message"] as? [String: Any], item["role"] as? String == "user" {
            // Tool result records are not new user turns.
            let blocks = item["content"] as? [[String: Any]] ?? []
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            guard blocks.allSatisfy({ ["text", "image"].contains($0["type"] as? String ?? "") }) else { return nil }
            let text = (item["content"] as? String) ?? blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if turn.isEmpty || claudeFinished {
                turn = row["uuid"] as? String ?? ""
                startedAt = row["timestamp"] as? String ?? ""
                userFacing = false; claudeFinished = false
            }
            claudePending = nil
            if observeUser(text,recordKey:recordKey) { return nil }
        }
        if row["type"] as? String == "assistant", let item = row["message"] as? [String: Any],
           item["role"] as? String == "assistant", item["stop_reason"] as? String == "end_turn",
           let blocks = item["content"] as? [[String: Any]],
           !blocks.contains(where: { $0["type"] as? String == "tool_use" }) {
            let observedUser = userFacing
            userFacing = false
            claudeFinished = true; claudePending = nil
            guard observedUser else { return nil }
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.contains("\u{001B}") else { return nil }
            return LiveChatMessage(body: String(text.prefix(8192)), senderAddress: nil, senderName: nil, kind: "reply")
        }
        return LiveChatMessage.claudeProgress(data, pending: &claudePending) ?? LiveChatMessage.parse(data, provider: provider)
    }
}

/// Exact IDs accepted by the opt-in, current-reply count probe.
public enum ReplyProbeID {
    public static func matches(_ id: String, session: String) -> Bool {
        if let range = id.range(of:resultIdPattern,options:.regularExpression), range == id.startIndex..<id.endIndex { return true }
        guard let parts = liveParts(id) else { return false }
        return parts[2] + ":" + parts[3] == session
    }
    public static func address(_ id: String) -> String? { liveParts(id)?[1] }
    private static func liveParts(_ id: String) -> [String]? {
        guard id.count <= 128 else { return nil }
        let parts = id.split(separator:":",omittingEmptySubsequences:false).map(String.init)
        guard parts.count == 5, parts[0] == "live",
              parts[1].range(of:#"\A[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)?\z"#,options:.regularExpression) != nil else { return nil }
        for value in parts[2...] {
            guard value.range(of:#"\A[1-9][0-9]*\z"#,options:.regularExpression) != nil, UInt64(value) != nil else { return nil }
        }
        guard Int64(parts[2]) != nil, Int64(parts[3]) != nil else { return nil }
        return parts
    }
}

/// Only newly observed final replies are persisted; transcripts are never reopened.
public final class LiveReplyArchive {
    private let url: URL
    public private(set) var entries: [[String: String]]
    public init(url: URL) {
        self.url = url
        entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([[String: String]].self, from: $0) } ?? []
    }
    public func append(_ entry: [String: String]) throws {
        guard entry["kind"] == "reply", !(entry["session"] ?? "").isEmpty,
              !(entry["turn"] ?? "").isEmpty, let id = entry["id"], !entries.contains(where: { $0["id"] == id }) else { return }
        var captured = entry
        captured.removeValue(forKey:"turnEndedAt")
        if let start = Self.instant(entry["turnStartedAt"]), let final = Self.instant(entry["at"]), final >= start {
            captured["turnEndedAt"] = entry["at"]
        }
        var next = entries; next.append(captured)
        try save(next)
    }
    public func complete(turn: String, session: String, address: String, at: String) throws {
        let next = entries.map { entry -> [String: String] in
            guard entry["turn"] == turn, entry["session"] == session, entry["fromAddress"] == address,
                  let start = Self.instant(entry["turnStartedAt"]), let final = Self.instant(entry["at"]),
                  let complete = Self.instant(at), final >= start, complete >= final,
                  complete >= (Self.instant(entry["turnEndedAt"]) ?? final) else { return entry }
            var entry = entry; entry["turnEndedAt"] = at; return entry
        }
        if next != entries { try save(next) }
    }
    private func save(_ next: [[String: String]]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        entries = next
    }
    private static func instant(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from:value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from:value)
    }
}
