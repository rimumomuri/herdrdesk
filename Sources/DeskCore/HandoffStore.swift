import Foundation
import Darwin

/// Persists the handoff book as one private JSON file, replaced atomically.
public final class HandoffStore {
    private struct File: Codable { var edges: [HandoffEdge]; var cards: [HandoffCard] }
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func defaultURL() -> URL { DeskPaths.data.appendingPathComponent("handoffs.json") }

    /// Unreadable or corrupt state starts empty; open edges come back as unconfirmed.
    public func load() -> HandoffBook {
        guard let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024,
              let file = try? JSONDecoder().decode(File.self, from: data) else { return HandoffBook() }
        let book = HandoffBook(edges: file.edges, cards: file.cards)
        book.markReloaded()
        return book
    }

    public func save(_ book: HandoffBook) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(File(edges: book.edges, cards: book.cards))
        let temporary = dir.appendingPathComponent(".handoffs-" + UUID().uuidString)
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data); try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch { try? handle.close(); unlink(temporary.path); throw error }
    }
}
