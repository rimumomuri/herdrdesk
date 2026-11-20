import Foundation

extension LiveChatMessage {
    /// The first `hc send <target> <text>` a Claude Bash tool call or a Codex shell call runs.
    /// Only the command string is read; tool output never is. Anything ambiguous is nil:
    /// a missed handoff is better than an invented one.
    public static func outgoingSend(_ data: Data, provider: String) -> (target: String, body: String)? {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var commands: [String] = []
        if provider == "claude-code" {
            guard row["type"] as? String == "assistant", row["isSidechain"] as? Bool != true,
                  let message = row["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] else { return nil }
            for block in blocks where block["type"] as? String == "tool_use" && block["name"] as? String == "Bash" {
                if let command = (block["input"] as? [String: Any])?["command"] as? String { commands.append(command) }
            }
        } else if provider == "codex" {
            guard row["type"] as? String == "response_item", let item = row["payload"] as? [String: Any],
                  item["type"] as? String == "function_call", ["exec_command", "shell"].contains(item["name"] as? String ?? ""),
                  let raw = item["arguments"] as? String, let args = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { return nil }
            if let cmd = args["cmd"] as? String { commands.append(cmd) }
            else if let cmd = args["command"] as? String { commands.append(cmd) }
            else if let list = args["command"] as? [String], let last = list.last { commands.append(last) }
        }
        for command in commands { if let found = hcSend(in: command) { return found } }
        return nil
    }

    static func hcSend(in command: String) -> (target: String, body: String)? {
        let pattern = #"(?:\A|&&|\|\||;|\n|\()[ \t]*(?:[^\s;&|()]*/)?hc[ \t]+send[ \t]+"#
        guard command.count <= 65_536, let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range, in: command),
              let words = shellWords(String(command[range.upperBound...])) else { return nil }
        var rest = words[...]
        while let first = rest.first, first.hasPrefix("--") { rest = rest.dropFirst() }
        guard let target = rest.first, target.range(of: #"\A[A-Za-z0-9._/-]{1,96}\z"#, options: .regularExpression) != nil else { return nil }
        let body = rest.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return (target, String(body.prefix(8192)))
    }

    /// Words up to the end of the simple command. Supports '…', "…" (with \" \\ \$ \`) and
    /// "$(cat <<'EOF' … EOF\n)" heredoc bodies. Returns nil for anything else that needs a shell.
    static func shellWords(_ text: String) -> [String]? {
        let chars = Array(text)
        var words: [String] = [], word = "", inWord = false, i = 0
        func flush() { if inWord { words.append(word); word = ""; inWord = false } }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ", "\t": flush(); i += 1
            case "\n", ";", "&", "|", ")": flush(); return words
            case "'":
                guard let end = chars[(i + 1)...].firstIndex(of: "'") else { return nil }
                word += String(chars[(i + 1)..<end]); inWord = true; i = end + 1
            case "\"":
                i += 1; inWord = true
                var closed = false
                while i < chars.count {
                    let d = chars[i]
                    if d == "\"" { closed = true; i += 1; break }
                    if d == "\\", i + 1 < chars.count, "\"\\$`".contains(chars[i + 1]) { word.append(chars[i + 1]); i += 2; continue }
                    if d == "$", i + 1 < chars.count, chars[i + 1] == "(" {
                        guard let (body, next) = heredoc(chars, from: i) else { return nil }
                        word += body; i = next; continue
                    }
                    if d == "$" || d == "`" { return nil }
                    word.append(d); i += 1
                }
                if !closed { return nil }
            case "$", "`", "<", ">", "(": return nil
            case "\\":
                guard i + 1 < chars.count else { return nil }
                word.append(chars[i + 1]); inWord = true; i += 2
            default: word.append(c); inWord = true; i += 1
            }
        }
        flush()
        return words
    }

    /// `$(cat <<'EOF'\n…\nEOF\n)` starting at `$`: the body and the index after `)`.
    private static func heredoc(_ chars: [Character], from start: Int) -> (String, Int)? {
        let tail = String(chars[start...])
        let pattern = #"\A\$\(cat <<-?['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?\n([\s\S]*?)\n[ \t]*\1[ \t]*\n?[ \t]*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let body = Range(m.range(at: 2), in: tail), let whole = Range(m.range, in: tail) else { return nil }
        return (String(tail[body]), start + tail.distance(from: tail.startIndex, to: whole.upperBound))
    }
}
