import Foundation

/// Results a member explicitly published with `herdr-result` (never inferred from working/done or conversations).
/// Files: <root>/<role>/<id>.json. A record is accepted only when its role/id match the folder and file name.
public struct ResultRecord: Equatable {
    public var id, role, team, display, session, at, title, summary, body, flow, state: String
    public var artifacts: [(path: String, bytes: Int)]
    public var kind: String = "report"
    public var recipient: String = ""
    public static func == (a: ResultRecord, b: ResultRecord) -> Bool { a.id == b.id && a.state == b.state && a.at == b.at }
    public var withdrawn: Bool { state != "published" }
}

public let resultIdPattern = "^r[0-9]{14}[0-9a-f]{6}$"
let rolePattern = "^[A-Za-z0-9._-]{1,64}$"
func matches(_ s: String, _ p: String) -> Bool { s.range(of: p, options: .regularExpression) != nil }

public final class ResultStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    public static func defaultRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let r = environment["HERDRDESK_RESULTS"], !r.isEmpty { return URL(fileURLWithPath: r, isDirectory: true) }
        if DeskPaths.retainsLegacyProfile {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/herdr-desk/results", isDirectory: true)
        }
        return DeskPaths.data.appendingPathComponent("results", isDirectory: true)
    }

    /// Every valid record, newest first (by publish time), at most `perRole` per member.
    public func load(perRole: Int = 30) -> [ResultRecord] {
        let fm = FileManager.default
        guard let roles = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var out: [ResultRecord] = []
        for role in roles where matches(role, rolePattern) && role != "." && role != ".." {
            let dir = root.appendingPathComponent(role, isDirectory: true)
            guard let dirInfo = try? dir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  dirInfo.isDirectory == true, dirInfo.isSymbolicLink != true else { continue }
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            var mine: [ResultRecord] = []
            for f in files where f.hasSuffix(".json") && !f.hasPrefix(".") {
                let id = String(f.dropLast(5))
                guard matches(id, resultIdPattern) else { continue }
                let url = dir.appendingPathComponent(f)
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), v.isRegularFile == true, v.isSymbolicLink != true,
                      let d = try? Data(contentsOf: url), d.count < 512 * 1024,
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      (j["id"] as? String) == id, (j["role"] as? String) == role else { continue }   // half-written or mismatched: ignored
                let s = { (k: String) in (j[k] as? String) ?? "" }
                let arts = (j["artifacts"] as? [[String: Any]] ?? []).prefix(8).compactMap { a -> (String, Int)? in
                    guard let p = a["path"] as? String else { return nil }; return (p, (a["bytes"] as? NSNumber)?.intValue ?? 0) }
                mine.append(ResultRecord(id: id, role: role, team: s("team"), display: s("display"), session: s("session"), at: s("at"),
                                         title: String(s("title").prefix(80)), summary: String(s("summary").prefix(200)),
                                         body: String(s("body").prefix(64 * 1024)), flow: s("flow"), state: s("state").isEmpty ? "published" : s("state"),
                                         artifacts: arts.map { (path: $0.0, bytes: $0.1) }, kind: s("kind").isEmpty ? "report" : s("kind"),
                                         recipient: matches(s("recipient"), rolePattern) && ![".", ".."].contains(s("recipient")) ? s("recipient") : ""))
            }
            for group in Dictionary(grouping: mine, by: { $0.kind }).values {
                out += group.sorted { $0.at > $1.at }.prefix(perRole)
            }
        }
        return out.filter { $0.state != "pruned" }.sorted { $0.at > $1.at }
    }

    public func find(id: String) -> ResultRecord? { matches(id, resultIdPattern) ? load().first { $0.id == id } : nil }
}

/// What a click on a deliverable may do. Paths come from the record (never from the page) and are checked again.
public enum ArtifactAction: Equatable { case open(URL), reveal(URL), refuse(String) }

public enum ArtifactPolicy {
    /// Opened with the default app only when the type is a plain document/media AND not executable.
    static let openable: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "pdf", "txt", "md", "markdown", "json", "csv", "log",
                                        "mov", "mp4", "m4v", "m4a", "mp3", "wav"]
    static let secretNames = ["^\\.env", "^id_(rsa|dsa|ecdsa|ed25519)", "\\.(pem|key|p12|pfx|keychain|keychain-db|kdbx)$",
                              "credentials", "secret", "token"]

    public static func decide(_ recorded: String, home: String = NSHomeDirectory()) -> ArtifactAction {
        let fm = FileManager.default
        guard recorded.hasPrefix("/") else { return .refuse("경로가 올바르지 않아요.") }
        let url = URL(fileURLWithPath: recorded).standardizedFileURL
        let real = url.resolvingSymlinksInPath()
        let homeReal = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        guard real.path == url.path else { return .refuse("심볼릭 링크를 거치는 경로는 열지 않아요.") }
        guard real.path.hasPrefix(homeReal + "/") else { return .refuse("홈 폴더 밖의 파일은 열지 않아요.") }
        let rel = String(real.path.dropFirst(homeReal.count + 1))
        if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) || rel.hasPrefix("Library/Keychains") {
            return .refuse("숨김·비밀 위치의 파일은 열지 않아요.")
        }
        let name = real.lastPathComponent.lowercased()
        if secretNames.contains(where: { matches(name, $0) }) { return .refuse("비밀 정보로 보이는 파일은 열지 않아요.") }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: real.path, isDirectory: &isDir), !isDir.boolValue,
              let attrs = try? fm.attributesOfItem(atPath: real.path), (attrs[.type] as? FileAttributeType) == .typeRegular
        else { return .refuse("파일이 없어요(옮겨졌거나 지워졌을 수 있어요).") }
        let ext = real.pathExtension.lowercased()
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        if !openable.contains(ext) || perms & 0o111 != 0 || looksExecutable(real) { return .reveal(real) }
        return .open(real)
    }

    /// A "document" whose bytes are a Mach-O binary or a script is only shown in Finder.
    static func looksExecutable(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? h.close() }
        let b = [UInt8](h.readData(ofLength: 4))
        if b.count >= 2, b[0] == 0x23, b[1] == 0x21 { return true }                       // #!
        let magic: [[UInt8]] = [[0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE], [0xFE, 0xED, 0xFA, 0xCF]]
        return b.count == 4 && magic.contains(b)
    }
}

/// Which results the person has read (id → time). Kept across restarts.
public final class ResultReads {
    let url: URL
    public private(set) var data: [String: String] = [:]
    public init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: String].self, from: d) { data = m }
    }
    public static func defaultURL() -> URL { DeskPaths.data.appendingPathComponent("results-read.json") }
    public func markRead(_ id: String, at: String) {
        guard matches(id, resultIdPattern), data[id] == nil else { return }
        data[id] = at
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(data).write(to: url, options: .atomic)
    }
}

/// Clicked links must occur literally in the recorded assistant reply. Never load them in WebView.
public enum ReplyLinkPolicy {
    public static func decide(_ target: String, body: String, home: String = NSHomeDirectory()) -> ArtifactAction {
        guard !target.isEmpty, target.count <= 4096, !target.unicodeScalars.contains(where: { $0.value < 32 }),
              body.contains("](\(target))") else { return .refuse("답장에 있는 링크를 다시 확인해 주세요.") }
        if target.hasPrefix("/"), !target.hasPrefix("//") { return ArtifactPolicy.decide(target, home: home) }
        guard let url = URL(string: target), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
        else { return .refuse("이 링크 형식은 열지 않아요.") }
        return .open(url)
    }
}
