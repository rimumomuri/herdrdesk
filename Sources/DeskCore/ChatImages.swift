import Foundation
import ImageIO
import Darwin
import CryptoKit

/// The page identifies an already accepted record; it never supplies a readable path.
public struct ChatImageRecord: Equatable {
    public let id, role, session, body: String
    public init(id: String, role: String, session: String, body: String) {
        self.id=id; self.role=role; self.session=session; self.body=body
    }
    public func matches(id: String, role: String, session: String, body: String) -> Bool {
        !self.id.isEmpty && !self.role.isEmpty && !self.session.isEmpty && self.id == id && self.role == role && self.session == session && self.body == body
    }
    public func previews(home: String = NSHomeDirectory()) -> [[String: String]] {
        ChatImagePolicy.references(body).map { path in
            ["name":URL(fileURLWithPath:path).lastPathComponent,
             "thumbnail":ChatImagePolicy.thumbnail(path,home:home)?.base64EncodedString() ?? ""]
        }
    }
}

public enum ChatImagePolicy {
    public static let maxBytes = 10 * 1024 * 1024
    public static let maxThumbnailBytes = 128 * 1024
    /// The image viewer's size: big enough to read a screenshot, bounded so one message never moves megabytes.
    public static let maxPreviewSide = 1600, maxPreviewBytes = 3 * 1024 * 1024
    private static let extensions: Set<String> = ["png","jpg","jpeg","gif","webp","heic","tiff","tif"]
    /// Intentionally narrow: Markdown image/document links to images, or a complete image-path line.
    /// Code fences, indented code, inline code, prose paths and URLs do not request a file read.
    public static func references(_ body: String) -> [String] {
        var paths: [String] = [], fence: String?
        for line in body.prefix(8192).components(separatedBy:"\n") {
            let fenceRE=try! NSRegularExpression(pattern:#"^ {0,3}(`{3,}|~{3,})(.*)$"#)
            let match=fenceRE.firstMatch(in:line,range:NSRange(line.startIndex...,in:line))
            if fence != nil || match != nil {
                if let match, let markerRange=Range(match.range(at:1),in:line), let tailRange=Range(match.range(at:2),in:line) {
                    let marker=String(line[markerRange])
                    if let opened=fence {
                        if marker.first == opened.first && marker.count >= opened.count && line[tailRange].trimmingCharacters(in:.whitespaces).isEmpty { fence=nil }
                    } else { fence=marker }
                }
                continue
            }
            guard !line.hasPrefix("    "), !line.hasPrefix("\t") else { continue }
            // Conservatively skip mixed inline-code lines as well as fenced code.
            guard !line.contains("`") else { continue }
            let plain=line
            let pattern = #"!?\[[^\]\n]*\]\((?:<(/[^>\n]+)>|(/[^\s()]+))\)"#
            let regex=try! NSRegularExpression(pattern:pattern)
            for match in regex.matches(in:plain,range:NSRange(plain.startIndex...,in:plain)) {
                let capture=match.range(at:1).location == NSNotFound ? match.range(at:2) : match.range(at:1)
                if let range=Range(capture,in:plain), let whole=Range(match.range,in:plain) {
                    if whole.lowerBound > plain.startIndex && plain[plain.index(before:whole.lowerBound)] == "\\" { continue }
                    let path=String(plain[range])
                    if plain[whole].hasPrefix("![") || extensions.contains(URL(fileURLWithPath:path).pathExtension.lowercased()) { paths.append(path) }
                }
            }
            let standalone=plain.trimmingCharacters(in:.whitespaces)
            if standalone.hasPrefix("/"), !standalone.contains("]("), extensions.contains(URL(fileURLWithPath:standalone).pathExtension.lowercased()) { paths.append(standalone) }
        }
        var seen=Set<String>()
        return Array(paths.filter { path in
            path.hasPrefix("/") && !path.hasPrefix("//") && path.count <= 4096 && !path.unicodeScalars.contains(where:{$0.value < 32}) && seen.insert(path).inserted
        }.prefix(4))
    }

    /// Reuse the existing document policy, with a smaller automatic-read surface.
    /// No hidden-root exception is enabled without a concrete product-owned media root.
    public static func thumbnail(_ path: String, home: String = NSHomeDirectory()) -> Data? {
        guard let data=readAllowed(path,home:home) else { return nil }
        return boundedThumbnail(data)
    }

    /// The same file rules as the thumbnail, at viewer size (longest side ≤ maxPreviewSide, PNG ≤ maxPreviewBytes).
    public static func largePreview(_ path: String, home: String = NSHomeDirectory()) -> Data? {
        guard let data=readAllowed(path,home:home), let source=boundedSource(data),
              let image=AttachmentStore.thumbnail(source,max:maxPreviewSide), image.count <= maxPreviewBytes else { return nil }
        return image
    }

    private static func readAllowed(_ path: String, home: String) -> Data? {
        let root=URL(fileURLWithPath:home).standardizedFileURL.resolvingSymlinksInPath().path
        let url=URL(fileURLWithPath:path).standardizedFileURL
        guard path == url.path, extensions.contains(url.pathExtension.lowercased()),
              ["Pictures","Downloads","Documents","workspace"].contains(where:{path.hasPrefix(root+"/"+$0+"/")}),
              !url.pathComponents.contains(where: { part in
                  ArtifactPolicy.secretNames.contains(where: { matches(part.lowercased(),$0) })
              }), case .open = ArtifactPolicy.decide(path,home:home) else { return nil }
        // openat with O_NOFOLLOW on every component closes the validation/open symlink race.
        return readRegularFile(path,maxBytes:maxBytes)
    }

    static func readRegularFile(_ path: String, maxBytes: Int) -> Data? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let components=path.split(separator:"/").map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains(".") else { return nil }
        var fd=open("/",O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return nil }
        for (index,part) in components.enumerated() {
            let next=openat(fd,part,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | (index < components.count-1 ? O_DIRECTORY : 0))
            close(fd); fd=next
            if fd < 0 { return nil }
        }
        defer { close(fd) }
        var info=stat()
        guard fstat(fd,&info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o111 == 0, info.st_size > 0, info.st_size <= maxBytes else { return nil }
        var data=Data(), buffer=[UInt8](repeating:0,count:64*1024)
        while data.count <= maxBytes {
            let count=read(fd,&buffer,min(buffer.count,maxBytes+1-data.count))
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(contentsOf:buffer.prefix(count))
        }
        return data.count <= maxBytes ? data : nil
    }

    public static func boundedThumbnail(_ data: Data) -> Data? {
        guard let source=boundedSource(data), let thumbnail=AttachmentStore.thumbnail(source), thumbnail.count <= maxThumbnailBytes else { return nil }
        return thumbnail
    }

    /// A decodable image within the byte, axis and pixel limits.
    static func boundedSource(_ data: Data) -> CGImageSource? {
        guard !data.isEmpty, data.count <= maxBytes,
              let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=props[kCGImagePropertyPixelWidth] as? Int, let height=props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 40_000_000 else { return nil }
        return source
    }
}

/// Sanitized sent thumbnails, not original paths or message bodies. Specific ID reads only, no scans.
/// The caller must also verify the direct-send ledger before exposing a saved record to WebKit.
public final class SentChatImages {
    private let root: URL
    public init(root: URL) { self.root=root }
    private struct Stored: Codable {
        let id, role, session, digest: String
        let previews: [[String: String]]
    }
    private func url(_ id: String) -> URL? {
        guard matches(id,#"\Am[A-Za-z0-9_-]{6,60}\z"#) else { return nil }
        return root.appendingPathComponent(id+".json")
    }
    private func digest(_ body: String) -> String { SHA256.hash(data:Data(body.utf8)).map { String(format:"%02x",$0) }.joined() }
    public func save(_ record: ChatImageRecord, previews: [[String: String]]) throws {
        guard let file=url(record.id), previews.count <= 4, !previews.isEmpty,
              previews.allSatisfy({ item in
                  guard let encoded=item["thumbnail"], encoded.count <= 174764 else { return false }
                  return encoded.isEmpty || Data(base64Encoded:encoded).flatMap { ChatImagePolicy.boundedThumbnail($0) } != nil
              }) else { return }
        let stored=Stored(id:record.id,role:record.role,session:record.session,digest:digest(record.body),previews:previews)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try JSONEncoder().encode(stored).write(to:file,options:.atomic)
    }
    public func load(_ record: ChatImageRecord) -> [[String: String]]? {
        guard let file=url(record.id), let data=ChatImagePolicy.readRegularFile(file.path,maxBytes:800*1024),
              let saved=try? JSONDecoder().decode(Stored.self,from:data), saved.id == record.id,
              saved.role == record.role, saved.session == record.session, saved.digest == digest(record.body),
              saved.previews.count <= 4 else { return nil }
        return saved.previews
    }
}
