import Foundation

public enum ChatShortcut: Equatable {
    case website(URL)
    case folder(URL)
    case reveal(URL)
    /// A web page saved on this Mac: opened in the default browser.
    case browser(URL)
    /// A Markdown file: shown formatted inside the app.
    case markdown(URL)

    public static let markdownLimit = 2_000_000

    public static func destination(_ url: URL, home: String = NSHomeDirectory()) -> Self? {
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
            return .website(url)
        }
        let prefix = "herdrdesk-path:"
        guard url.absoluteString.hasPrefix(prefix),
              let path = url.absoluteString.dropFirst(prefix.count).removingPercentEncoding,
              path.utf8.count <= 4096, !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              path.hasPrefix("~/") || (path.hasPrefix("/") && !path.hasPrefix("//")) else { return nil }
        let expanded = path.hasPrefix("~/") ? home + String(path.dropFirst()) : path
        if let target = localItem(expanded) { return target }

        // A copied file reference may include its editor line and column.
        let file = expanded.replacingOccurrences(of: #":[0-9]+(?::[0-9]+)?$"#, with: "", options: .regularExpression)
        return file == expanded ? nil : localItem(file)
    }

    private static func localItem(_ path: String) -> Self? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .isSymbolicLinkKey]) else { return nil }
        if info.isSymbolicLink == true || info.isPackage == true { return .reveal(url) }
        if info.isDirectory == true { return .folder(url) }
        guard info.isRegularFile == true else { return nil }
        switch url.pathExtension.lowercased() {
        case "html", "htm": return .browser(url)
        case "md", "markdown": return .markdown(url)
        default: return .reveal(url)
        }
    }

    /// The text of a Markdown file, or nil when it is too large or not UTF-8.
    public static func markdownText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data: Data
        do { data = try handle.read(upToCount: markdownLimit + 1) ?? Data() } catch { return nil }
        guard data.count <= markdownLimit else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
