import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images the person attached in the composer, kept per member until sent (drafts survive restarts).
/// Every file is decoded with ImageIO first: only real images are kept; PNG/JPEG stay as they are,
/// anything else ImageIO can read (HEIC, WebP, GIF, TIFF…) is re-encoded as PNG.
public struct Attachment: Codable, Equatable {
    public var id: String
    public var name: String
    public var file: String        // absolute path in the drafts folder
    public var bytes: Int
    public var width: Int
    public var height: Int
}

public enum AttachError: Error, Equatable, CustomStringConvertible {
    case tooBig, notImage, tooMany, badRole, io(String)
    public var description: String {
        switch self {
        case .tooBig: return "이미지가 너무 커요(원본 25MB, 전달용 5MB 이하)."
        case .notImage: return "이미지 파일만 첨부할 수 있어요."
        case .tooMany: return "한 메시지에 이미지는 4장까지예요."
        case .badRole: return "보낼 담당을 확인할 수 없어요."
        case .io(let s): return "첨부 파일을 저장하지 못했어요: \(s)"
        }
    }
}

public final class AttachmentStore {
    public static let maxBytes = 10 * 1024 * 1024
    public static let maxCount = 4
    public let root: URL
    public init(root: URL) { self.root = root }
    public static func defaultRoot() -> URL { DeskPaths.data.appendingPathComponent("attachments", isDirectory: true) }

    private func roleDir(_ role: String) -> URL? {
        guard role != ".", role != "..", role.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else { return nil }
        return root.appendingPathComponent("drafts", isDirectory: true).appendingPathComponent(role, isDirectory: true)
    }
    private func indexURL(_ role: String) -> URL? { roleDir(role)?.appendingPathComponent("index.json") }

    public func list(role: String) -> [Attachment] {
        guard let u = indexURL(role), let dir = roleDir(role),
              let d = try? Data(contentsOf: u) else { return [] }
        let root = dir.standardizedFileURL.resolvingSymlinksInPath().path
        return ((try? JSONDecoder().decode([Attachment].self, from: d)) ?? []).filter { entry in
            let file = URL(fileURLWithPath: entry.file)
            guard file.deletingLastPathComponent().resolvingSymlinksInPath().path == root,
                  let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true else { return false }
            return true
        }
    }
    public func rolesWithDrafts() -> [String] {
        let folder = root.appendingPathComponent("drafts", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix("session-") && !list(role: $0).isEmpty }.sorted()
    }

    private func save(role: String, _ items: [Attachment]) throws {
        guard let u = indexURL(role) else { throw AttachError.badRole }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: u, options: .atomic)
    }

    /// Store one image for a member's draft (research hq-desk-image-attach-20261113):
    /// decode with ImageIO (only real images; GIF → first frame), apply orientation, longest side ≤ 2000 px,
    /// re-encode WITHOUT metadata (EXIF/GPS dropped): JPEG sources stay JPEG, everything else PNG; ≤ 5 MB
    /// (falls back to JPEG). ASCII file name herdr-img-<ts>-<rand>.<ext>. Returns the record and a thumbnail.
    public static let maxInput = 25 * 1024 * 1024, maxOutput = 5 * 1024 * 1024, maxSide = 2000
    public func add(role: String, name: String, data: Data) throws -> (Attachment, Data) {
        guard let dir = roleDir(role) else { throw AttachError.badRole }
        if data.count > AttachmentStore.maxInput { throw AttachError.tooBig }
        var items = list(role: role)
        if items.count >= AttachmentStore.maxCount { throw AttachError.tooMany }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0,
              let type = CGImageSourceGetType(src) as String?,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w0 = props[kCGImagePropertyPixelWidth] as? Int, let h0 = props[kCGImagePropertyPixelHeight] as? Int, w0 > 0, h0 > 0
        else { throw AttachError.notImage }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: min(AttachmentStore.maxSide, max(w0, h0))]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw AttachError.notImage }
        func encode(_ uti: UTType, quality: Double?) -> Data? {
            let out = NSMutableData()
            guard let dst = CGImageDestinationCreateWithData(out, uti.identifier as CFString, 1, nil) else { return nil }
            let p: [CFString: Any] = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] } ?? [:]
            CGImageDestinationAddImage(dst, img, p as CFDictionary)
            return CGImageDestinationFinalize(dst) ? out as Data : nil
        }
        var uti: UTType = type == UTType.jpeg.identifier ? .jpeg : .png
        var bytes = encode(uti, quality: uti == .jpeg ? 0.88 : nil)
        if (bytes?.count ?? Int.max) > AttachmentStore.maxOutput { uti = .jpeg; bytes = encode(.jpeg, quality: 0.8) }
        if (bytes?.count ?? Int.max) > AttachmentStore.maxOutput { bytes = encode(.jpeg, quality: 0.6) }
        guard let enc = bytes, enc.count <= AttachmentStore.maxOutput else { throw AttachError.tooBig }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000)), rand = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        let id = "a\(stamp)\(rand)"
        let file = dir.appendingPathComponent("herdr-img-\(stamp)-\(rand).\(uti == .jpeg ? "jpg" : "png")")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try enc.write(to: file, options: .atomic)
        } catch { throw AttachError.io(error.localizedDescription) }
        let rec = Attachment(id: id, name: name.isEmpty ? "image" : String(name.prefix(80)), file: file.path, bytes: enc.count,
                             width: img.width, height: img.height)
        items.append(rec)
        do { try save(role: role, items) } catch { try? FileManager.default.removeItem(at: file); throw AttachError.io(error.localizedDescription) }
        return (rec, AttachmentStore.thumbnail(src) ?? Data())
    }

    public func remove(role: String, id: String) {
        var items = list(role: role)
        if let i = items.firstIndex(where: { $0.id == id }) { try? FileManager.default.removeItem(atPath: items[i].file); items.remove(at: i) }
        try? save(role: role, items)
    }

    /// Only ids that really are in this member's draft (the page's list is never trusted for paths).
    public func resolve(role: String, ids: [String]) -> [Attachment]? {
        let items = list(role: role)
        var out: [Attachment] = []
        for id in ids { guard let a = items.first(where: { $0.id == id }) else { return nil }; out.append(a) }
        return out
    }

    /// After a confirmed send the draft images are no longer needed in the drafts folder.
    public func clear(role: String, ids: [String]) { for id in ids { remove(role: role, id: id) } }

    public static func thumbnail(_ src: CGImageSource, max: Int = 192) -> Data? {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let t = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, t, nil)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
    public func thumbnail(for a: Attachment) -> Data? {
        guard let data = ChatImagePolicy.readRegularFile(a.file, maxBytes: ChatImagePolicy.maxBytes) else { return nil }
        return ChatImagePolicy.boundedThumbnail(data)
    }
}
