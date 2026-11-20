import Foundation

/// App data: ~/Library/Application Support/app.herdrdesk, or HERDRDESK_DATA (tests and fixture demos,
/// so a demo never shares a ledger or lock with the real app).
public enum DeskPaths {
    public static var data: URL {
        if let d = ProcessInfo.processInfo.environment["HERDRDESK_DATA"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            retainsLegacyProfile ? "Library/Application Support/HerdrDesk" : "Library/Application Support/app.herdrdesk",
            isDirectory: true)
    }

    public static var retainsLegacyProfile: Bool {
        Bundle.main.object(forInfoDictionaryKey: "HerdrDeskLegacyProfile") as? Bool == true
    }
}

/// Exclusive local lock shared by every sender on this Mac (HerdrDesk copies, later the Herdr mod):
/// `~/Library/Application Support/app.herdrdesk/send.lock`. flock is released when the process exits.
public final class FileLock {
    private var fd: Int32
    private let mutex = NSLock()
    private init(fd: Int32) { self.fd = fd }
    public static func tryAcquire(path: String) -> FileLock? {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); return nil }
        return FileLock(fd: fd)
    }
    /// Idempotent: the descriptor is closed exactly once, so a later release (or deinit) can never
    /// close a descriptor number that another thread has reopened in the meantime.
    public func release() {
        mutex.lock(); defer { mutex.unlock() }
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN); close(fd); fd = -1
    }
    public var isHeld: Bool { mutex.lock(); defer { mutex.unlock() }; return fd >= 0 }
    deinit { release() }
}

/// One record per question id, written BEFORE hc send. Its presence blocks a second send of the
/// same question from any window, across restarts. hc labels are informational only (not CAS).
public struct LedgerEntry: Codable, Equatable {
    /// sending | sent | not_sent | needs_check | resolved_sent | resolved_not_sent
    public var state: String
    public var role: String
    public var address: String
    public var session: String
    public var at: String
    public var turn: Int?
    public var note: String?
}

public final class Ledger {
    public let dir: URL
    public init(dir: URL) { self.dir = dir }
    public static func defaultDir() -> URL { DeskPaths.data.appendingPathComponent("ledger", isDirectory: true) }
    private func url(_ id: String) -> URL? {
        let ok = id.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil
        return ok ? dir.appendingPathComponent(id + ".json") : nil
    }
    public func read(_ id: String) -> LedgerEntry? {
        guard let u = url(id), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(LedgerEntry.self, from: d)
    }
    public func write(_ id: String, _ e: LedgerEntry) throws {
        guard let u = url(id) else { throw NSError(domain: "ledger", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad question id"]) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(e).write(to: u, options: .atomic)
    }
    /// A question may only be (re)sent when nothing was recorded, or the last try surely did not start.
    public func allowsSend(_ id: String) -> Bool {
        guard let e = read(id) else { return true }
        return e.state == "not_sent" || e.state == "resolved_not_sent"
    }
}
