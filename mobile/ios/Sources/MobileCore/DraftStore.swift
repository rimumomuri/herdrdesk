import Foundation

public struct DraftScope: Codable, Hashable, Sendable {
    public let endpoint: String
    public let mode: String
    public let conversation: String
    public let address: String
    public let session: String
    public let role: String
    public init(endpoint: String, mode: String, conversation: String, address: String, session: String, role: String) {
        self.endpoint = endpoint; self.mode = mode; self.conversation = conversation
        self.address = address; self.session = session; self.role = role
    }
}
public final class DraftStore {
    private struct Entry: Codable { var scope: DraftScope; var text: String }
    private let file: URL
    private var entries: [Entry]
    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
        } else { entries = [] }
    }
    public func text(for scope: DraftScope) -> String { entries.first(where: { $0.scope == scope })?.text ?? "" }
    public func save(_ text: String, for scope: DraftScope) throws {
        var next = entries.filter { $0.scope != scope }
        if !text.isEmpty { next.append(Entry(scope: scope, text: text)) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(next)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        entries = next
    }
}
