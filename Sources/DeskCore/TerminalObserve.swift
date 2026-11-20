import Foundation

struct ObserveFrame: Equatable {
    let channel: UInt32
    let kind: UInt8
    let payload: Data

    static func take(from buffer: inout Data) throws -> Self? {
        guard buffer.count >= 9 else { return nil }
        let start = buffer.startIndex
        let length = Int(readUInt32(buffer[(start + 5)..<(start + 9)]))
        guard length <= 16 * 1024 * 1024 else { throw ObserveError.protocolError }
        guard buffer.count >= 9 + length else { return nil }
        let frame = Self(channel: readUInt32(buffer[start..<(start + 4)]), kind: buffer[start + 4],
                         payload: Data(buffer[(start + 9)..<(start + 9 + length)]))
        buffer.removeFirst(9 + length)
        return frame
    }

    static func credit(channel: UInt32, count: UInt32) -> Self {
        Self(channel: channel, kind: 1, payload: littleEndian(count))
    }

    var encoded: Data {
        var data = Self.littleEndian(channel)
        data.append(kind)
        data.append(Self.littleEndian(UInt32(payload.count)))
        data.append(payload)
        return data
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func readUInt32(_ bytes: Data) -> UInt32 {
        bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }
}

private enum ObserveError: Error { case protocolError, disconnected }

/// A framed connection to a single, verified live terminal. Read-only is the default.
public final class TerminalObserver {
    public enum Event {
        case ready(cols: Int, rows: Int, followsSize: Bool)
        case size(cols: Int, rows: Int)
        case output(Data)
        case ended(String)
    }

    private let queue = DispatchQueue(label: "herdrdesk.terminal-observer", qos: .utility)
    private let path: String
    private let target: Term
    private let interactive: Bool
    private let notify: (Event) -> Void
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var framed = false
    private var channel: UInt32?
    private var closed = false
    private var outstanding = 0

    public init(path: String, target: Term, interactive: Bool = false, notify: @escaping (Event) -> Void) {
        self.path = path
        self.target = target
        self.interactive = interactive
        self.notify = notify
    }

    public func start() { queue.async { self.launch() } }

    public func stop() { queue.async { self.finish() } }

    /// Credit only bytes rendered by the current viewer. Core bounds uncredited output.
    public func consumed(_ count: Int) {
        queue.async {
            guard !self.closed, let channel = self.channel, count > 0, count <= self.outstanding else { return }
            self.outstanding -= count
            do { try self.write(ObserveFrame.credit(channel: channel, count: UInt32(count)).encoded) }
            catch { self.finish("터미널 연결이 끊겼습니다.") }
        }
    }

    public func type(_ bytes: Data) {
        guard interactive, !bytes.isEmpty, bytes.count <= 32 * 1024 else { return }
        queue.async {
            guard !self.closed, let channel = self.channel else { return }
            do { try self.write(ObserveFrame(channel: channel, kind: 0, payload: bytes).encoded) }
            catch { self.finish("터미널 입력 연결이 끊겼습니다.") }
        }
    }

    private func launch() {
        guard !closed, process == nil else { return }
        let p = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["connect"]
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        if let input { _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) }
        do {
            try p.run()
            process = p
            output?.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                self?.queue.async { [weak self] in self?.consume(bytes) }
            }
            try writeRequest(id: 1, method: "hello", params: ["framed": true, "generation": 1,
                                                            "features": ["resize_notifications"]])
            queue.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.channel == nil else { return }
                self.finish("터미널 연결 시간이 초과됐습니다.")
            }
        } catch {
            finish("터미널을 연결하지 못했습니다.")
        }
    }

    private func consume(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty else { finish("터미널 연결이 끝났습니다."); return }
        buffer.append(data)
        do {
            if !framed {
                guard let newline = buffer.firstIndex(of: 10) else {
                    if buffer.count > 65536 { throw ObserveError.protocolError }
                    return
                }
                let json = try object(Data(buffer[..<newline]))
                guard let hello = json["result"] as? [String: Any], hello["framed"] as? Bool == true else {
                    throw ObserveError.protocolError
                }
                buffer.removeSubrange(...newline)
                framed = true
                try writeRequest(id: 2, method: "terminal.attach", params: [
                    "terminal": target.address, "cols": interactive ? (target.cols ?? 80) : 80,
                    "rows": interactive ? (target.rows ?? 24) : 24, "observe": !interactive,
                    "history": 600, "resize_notifications": true
                ])
            }
            while !closed, let frame = try ObserveFrame.take(from: &buffer) { try handle(frame) }
        } catch {
            finish("실시간 터미널 연결을 확인할 수 없습니다.")
        }
    }

    private func handle(_ frame: ObserveFrame) throws {
        if frame.channel == 0, frame.kind == 0 {
            let json = try object(frame.payload)
            guard json["id"] as? Int == 2, channel == nil else { return }
            guard let attach = json["result"] as? [String: Any],
                  let stream = attach["channel"] as? UInt32, stream > 0,
                  let record = attach["terminal"] as? [String: Any],
                  let term = Term(json: record), term.isAgent == target.isAgent, term.session == target.session,
                  term.address == target.address || term.address == target.address.split(separator: "/").last.map(String.init),
                  term.labels["recovery.role"] == target.role, term.state == "live",
                  let cols = record["cols"] as? Int, let rows = record["rows"] as? Int, cols > 0, rows > 0 else {
                finish("선택한 담당의 현재 터미널을 확인할 수 없습니다.")
                return
            }
            channel = stream
            notify(.ready(cols: cols, rows: rows, followsSize: attach["resize_notifications"] as? Bool == true))
            return
        }
        guard frame.channel == channel else { return }
        switch frame.kind {
        case 0:
            guard !frame.payload.isEmpty else { return }
            outstanding += frame.payload.count
            notify(.output(frame.payload))
        case 2:
            finish("터미널 연결이 끝났습니다.")
        case 3:
            let grid = Array(frame.payload)
            guard grid.count == 4 else { throw ObserveError.protocolError }
            let cols = Int(grid[0]) | Int(grid[1]) << 8
            let rows = Int(grid[2]) | Int(grid[3]) << 8
            guard cols > 0, rows > 0 else { throw ObserveError.protocolError }
            notify(.size(cols: cols, rows: rows))
        default:
            break
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ObserveError.protocolError
        }
        return value
    }

    private func writeRequest(id: Int, method: String, params: [String: Any]) throws {
        var body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        if framed { body = ObserveFrame(channel: 0, kind: 0, payload: body).encoded }
        else { body.append(10) }
        try write(body)
    }

    private func write(_ data: Data) throws {
        guard let input else { throw ObserveError.disconnected }
        try input.write(contentsOf: data)
    }

    private func finish(_ reason: String? = nil) {
        guard !closed else { return }
        closed = true
        output?.readabilityHandler = nil
        try? output?.close()
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        output = nil
        input = nil
        process = nil
        buffer.removeAll()
        if let reason { notify(.ended(reason)) }
    }
}
