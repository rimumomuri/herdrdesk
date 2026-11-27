import Foundation

/// The saved roles, private to this user (0600 in a 0700 folder), written atomically.
public struct RecoveryStore {
    public let url: URL
    public init(url: URL = DeskPaths.data.appendingPathComponent("recovery.json")) { self.url = url }

    public func load() -> RecoveryRegistry {
        guard let data = try? Data(contentsOf: url), let registry = try? JSONDecoder().decode(RecoveryRegistry.self, from: data),
              registry.version == 1 else { return RecoveryRegistry() }
        return registry
    }

    /// Runs `body` while holding the recovery lock, shared by the app and `HerdrDesk --recovery`. Throws at once when
    /// another recovery or save holds it.
    public func exclusively<T>(_ body: () throws -> T) throws -> T {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(folder.appendingPathComponent(".recovery.lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RecoveryError("cannot open the recovery lock") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw RecoveryError("another recovery is already running") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    public func save(_ registry: RecoveryRegistry) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(registry)
        let temp = folder.appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw RecoveryError("cannot write the recovery list")
        }
        if rename(temp.path, url.path) != 0 {
            try? FileManager.default.removeItem(at: temp)
            throw RecoveryError("cannot save the recovery list")
        }
    }
}

public struct RecoveryReport: Codable, Equatable {
    public var at: String
    public var applied: Bool
    public var roles: [RecoveryPlanItem]
    public var ready: Bool
    public var retired: [String]
    /// Roles that a recovery could start now.
    public var resumable: Int { roles.filter { $0.action == .resume || $0.action == .create }.count }
    public var needsAttention: Int { roles.filter { ![.skip, .resume, .create, .submitted].contains($0.action) }.count }
}

/// Runs a check or a recovery. Only one at a time (the caller serializes on its own queue).
public struct RecoveryRunner {
    public let collector: RecoveryCollector
    let hc: HcRunning
    let locale: String
    let now: () -> String
    public init(hc: HcRunning, app: HcRunning?, locale: String, now: @escaping () -> String = RecoveryRunner.timestamp) {
        self.hc = hc; self.collector = RecoveryCollector(hc: hc, app: app); self.locale = locale; self.now = now
    }

    public static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    public func check(_ registry: RecoveryRegistry) throws -> RecoveryReport {
        try check(registry, runtime: collector.collect())
    }

    /// The same check on a picture already collected (the automatic save reuses its own).
    public func check(_ registry: RecoveryRegistry, runtime: RecoveryRuntime) -> RecoveryReport {
        let plan = Recovery.plan(registry, runtime: runtime, valid: collector.validator(for: registry.roles, runtime: runtime))
        return RecoveryReport(at: now(), applied: false, roles: plan, ready: plan.allSatisfy { $0.action == .skip }, retired: [])
    }

    /// Resumes every role that can be resumed, re-checking each one right before it starts.
    public func restore(_ registry: RecoveryRegistry) throws -> RecoveryReport {
        var runtime = try collector.collect()
        var plan = Recovery.plan(registry, runtime: runtime, valid: collector.validator(for: registry.roles, runtime: runtime))
        let roles = Dictionary(registry.roles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for index in plan.indices where plan[index].action == .resume || plan[index].action == .create {
            guard let role = roles[plan[index].key] else { continue }
            do {
                runtime = try collector.collect()
                let (actual, online) = try Recovery.resolve(role, in: runtime)
                let (action, reason) = Recovery.choose(role, actual, online: online)
                if action == .skip { plan[index].action = .skip; plan[index].reason = reason; plan[index].terminal = actual?.address; continue }
                guard action == plan[index].action else { throw RecoveryError("its state changed before the start: \(reason)") }
                let parent = Self.parentAddress(for: role.parentRole, in: registry, runtime: runtime)
                let args = try Recovery.runArguments(role, runtime: runtime, parent: parent, locale: locale, now: now())
                let result = hc.run(args, timeout: 60)
                guard result.code == 0, !result.timedOut, let data = result.out.data(using: .utf8),
                      let started = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let address = started["address"] as? String else {
                    throw RecoveryError("Herdr Core did not start it: " + String(result.err.suffix(200)))
                }
                _ = hc.run(["wait", address, "--timeout", "10"], timeout: 20)   // a start is not a finish; the final check decides
                plan[index].terminal = address
                plan[index].action = .submitted
            } catch {
                plan[index].action = .blocked
                plan[index].reason = "\(error)"
            }
        }
        let fresh = try collector.collect()
        let retired = retire(registry, runtime: fresh)
        var final = Recovery.plan(registry, runtime: fresh, valid: collector.validator(for: registry.roles, runtime: fresh))
        // A start that failed keeps its reason, unless the conversation runs now after all.
        for index in final.indices where final[index].action != .skip {
            if let attempt = plan.first(where: { $0.key == final[index].key && $0.action == .blocked }) {
                final[index].action = .blocked; final[index].reason = attempt.reason
            }
        }
        return RecoveryReport(at: now(), applied: true, roles: final, ready: final.allSatisfy { $0.action == .skip }, retired: retired)
    }

    /// Where a role's saved lead runs now: found through its own saved session, so an unlabelled lead is found too.
    public static func parentAddress(for key: String?, in registry: RecoveryRegistry, runtime: RecoveryRuntime) -> String? {
        guard let key, let parent = registry.roles.first(where: { $0.key == key }),
              let (actual, online) = try? Recovery.resolve(parent, in: runtime), let actual,
              Recovery.choose(parent, actual, online: online).0 == .skip else { return nil }
        return actual.address
    }

    /// Clears the launch mark of every saved role that is verified running (a slow start that finished later).
    public func clearLaunchMarks(_ registry: RecoveryRegistry, runtime: RecoveryRuntime) {
        for role in registry.roles {
            guard let (current, online) = try? Recovery.resolve(role, in: runtime), let current, current.launching,
                  Recovery.choose(role, current, online: online).0 == .skip else { continue }
            _ = hc.run(["label", current.address, "recovery.launching=", "recovery.launching-at="], timeout: 10)
        }
    }

    /// Once a role runs again, the shell it left behind gives up its role labels. The shell and its input stay.
    func retire(_ registry: RecoveryRegistry, runtime: RecoveryRuntime) -> [String] {
        var retired: [String] = []
        for role in registry.roles {
            guard let (current, online) = try? Recovery.resolve(role, in: runtime), let current,
                  Recovery.choose(role, current, online: online).0 == .skip else { continue }
            if current.launching { _ = hc.run(["label", current.address, "recovery.launching=", "recovery.launching-at="], timeout: 10) }
            for old in runtime.terminals where old.address != current.address && old.machine == role.machine
                && old.labels[Recovery.label] == role.key && old.shell {
                let result = hc.run(["label", old.address, Recovery.label + "=", "team.id=", "team.role=", "team.title=",
                                     "recovery.launching=", "recovery.launching-at=", "recovery.retired-role=" + role.key], timeout: 10)
                if result.code == 0 { retired.append(old.address) }
            }
        }
        return retired
    }
}
