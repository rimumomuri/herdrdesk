import Foundation
import DeskCore

final class EventPump {
    let hcPath: String
    let store = TerminalStore()
    let runner: ProcessHc
    let queue = DispatchQueue(label: "herdrdesk.events")
    var process: Process?
    var reading: FileHandle?
    var buffer = Data()
    var pending = Set<String>()
    var flushScheduled = false
    var stopped = false
    var gate = StreamGate()
    var onChange: (([[String: Any]], String, Int64?, [Term]) -> Void)?   // (terminals, connection state, lost at ms)

    init(hcPath: String) { self.hcPath = hcPath; runner = ProcessHc(path: hcPath) }

    func start() {
        queue.async { [weak self] in self?.launch() }
    }

    private func launch() {
        guard !stopped else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: hcPath)
        p.arguments = ["events", "--json"]
        gate.started()
        buffer.removeAll()                      // no partial line from an older stream
        let gen = gate.generation               // this process's identity: its callbacks are ignored once superseded
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let reader = out.fileHandleForReading
        reader.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil }   // EOF: an uncleared handler fires forever with empty data
            self?.queue.async { self?.consume(d, gen) }
        }
        p.terminationHandler = { [weak self] _ in
            self?.queue.async {
                reader.readabilityHandler = nil
                guard let self, !self.stopped, self.gate.isCurrent(gen) else { return }   // a superseded process's exit changes nothing
                self.buffer.removeAll()
                self.pending.removeAll()          // refreshes of the dead stream are void
                self.gate.lost(nowMs: Self.nowMs())
                self.emit()
                self.queue.asyncAfter(deadline: .now() + 3) { self.launch() }
            }
        }
        do { try p.run(); process = p; reading = reader } catch {
            reader.readabilityHandler = nil
            gate.lost(nowMs: Self.nowMs()); pending.removeAll()
            emit()
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.launch() }
        }
    }

    private func consume(_ d: Data, _ gen: Int) {
        if d.isEmpty || !gate.isCurrent(gen) { return }   // late output of a dead / older stream never reaches the store
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            switch store.apply(line: line) {
            case .snapshot: gate.snapshot(); emit()
            case .refresh(let a): if gate.live { pending.insert(a); scheduleFlush() }
            case .none: break
            }
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            let todo = self.pending; self.pending.removeAll()
            let gen = self.gate.generation
            var fetched: [(String, HcResult)] = []
            for a in todo { fetched.append((a, self.runner.run(["get", a], timeout: 10))) }
            // the stream may have died while we were reading: never apply or announce a stale refresh as live
            guard self.gate.accepts(gen) else { return }
            for (a, r) in fetched { self.store.apply(get: r, address: a) }
            self.emit()
        }
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Announce the table with the gate's current connection state (never a hard-coded "live").
    private func emit() {
        let list = store.publicList, conn = gate.conn, lost = gate.lostMs
        let terms = Array(store.terms.values)
        DispatchQueue.main.async { self.onChange?(list, conn, lost, terms) }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.reading?.readabilityHandler = nil
            self.reading = nil
            if let p = self.process, p.isRunning { p.terminate() }
            self.process = nil
        }
    }

    func terms() -> [Term] { queue.sync { Array(store.terms.values) } }
    /// Live only after a fresh snapshot of the current stream (never during a loss / reconnect).
    func isLive() -> Bool { queue.sync { gate.live } }
}
