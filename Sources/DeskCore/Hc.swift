import Foundation

/// Result of one hc invocation. `timedOut` means we stopped waiting: the outcome is unknown.
public struct HcResult {
    public var code: Int32
    public var out: String
    public var err: String
    public var timedOut: Bool
    public init(code: Int32, out: String, err: String, timedOut: Bool) {
        self.code = code; self.out = out; self.err = err; self.timedOut = timedOut
    }
}

public protocol HcRunning {
    func run(_ args: [String], timeout: TimeInterval) -> HcResult
}

/// Runs hc by absolute path with an argument array (never a shell string).
public final class ProcessHc: HcRunning {
    public let path: String
    public init(path: String) { self.path = path }

    /// The hc to use: HERDRDESK_HC (tests / demo fixture) or ~/.local/bin/hc. Finder-launched apps
    /// do not have ~/.local/bin on PATH, so PATH is never consulted.
    public static func resolvePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        resolveExecutable("hc", overrides: [environment["HERDRDESK_HC"]], environment: environment)
    }

    public static func resolveExecutable(_ name: String, overrides: [String?],
                                         environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let candidates = overrides.compactMap { $0 } + directories.map { $0 + "/" + name }
        return candidates.first { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func run(_ args: [String], timeout: TimeInterval) -> HcResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice
        // Set before run(): a fast hc can exit before a later assignment and its exit would be missed.
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch {
            // No reader was started yet, so nothing is left blocked on these pipes.
            return HcResult(code: -1, out: "", err: "cannot start hc: \(error)", timedOut: false)
        }
        let captured = Captured()
        let group = DispatchGroup()
        group.enter(); group.enter()
        DispatchQueue.global().async { captured.set(out: out.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        DispatchQueue.global().async { captured.set(err: err.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 2)
            _ = group.wait(timeout: .now() + 1)
            let (o, e) = captured.value
            return HcResult(code: -1, out: o, err: e, timedOut: true)
        }
        // A helper started by hc may keep the pipe open after hc exits; the exit status stays authoritative.
        _ = group.wait(timeout: .now() + 2)
        let (o, e) = captured.value
        return HcResult(code: p.terminationStatus, out: o, err: e, timedOut: false)
    }
}

/// Output gathered by the reader threads; read and written only under the lock.
private final class Captured: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    func set(out d: Data) { lock.lock(); out = d; lock.unlock() }
    func set(err d: Data) { lock.lock(); err = d; lock.unlock() }
    var value: (String, String) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
